#!/usr/bin/env ruby

require 'net/imap'
require 'net/http'
require 'mail'
require 'open-uri'
require 'fileutils'
require 'gmail'
require 'mime/types'

CONFIG = {
  :host               => 'imap.gmail.com',
  :username           => '[USERNAME]',
  :password           => '[PASSWORD]',
  :port               => 993,
  :ssl                => true,
  :processed_mailbox  => 'Processed',
  :url_regex          => /(imgur\.com\/[A-Z0-9.\/]+)/i,
  :url_file_regex     => /imgur\.com\/([A-Z0-9.\/]+)/i,
  :album_url_regex    => /data-src=\"http:\/\/i.imgur.com\/([A-Z0-9.]+)\"/i,
  :reddit_id_regex    => /reddit\.com\/tb\/([A-Z0-9]+)/i,
  :reddit_frame_regex => /reddit\.com\/toolbar\/inner\?id=([A-Z0-9_.-]+)/i,
  :reddit_base        => 'http://www.reddit.com/tb/',
  :reddit_frame_base  => 'http://www.reddit.com/toolbar/inner?id=',
  :reddit_title_regex => /<title>(.*?)<\/title>/i,
  :imgur_base         => 'http://imgur.com/',
  :image_dir          => 'images/',
  :pid_file           => 'mail_parser.pid'
}

def log(msg)
  puts "[#{Time.now.strftime('%Y-%m-%d %H:%M:%S')}] #{msg}"
  $stdout.flush
end

def get_lock()
  if ( File.file?(CONFIG[:pid_file]) )
    # Check pid file
    filePid = File.open(CONFIG[:pid_file], 'rb').read
    pids_text = `ps -e | awk '{print $1}'`.chomp
    pids = []
    pids_text.each_line() { |a| pids << a.chomp }

    # Yup, still going
    if ( pids.include?(filePid) )
      log("Running as #{filePid}")
      return false
    end

    # Nope, remove!
    log("Removing stale lock file")
    File.delete(CONFIG[:pid_file])
  end
  File.open(CONFIG[:pid_file], 'w') { |f| f.write(Process.pid) }
  return true
end

def free_lock
  if ( File.file?(CONFIG[:pid_file]) )
    File.delete(CONFIG[:pid_file])
    return true
  end
  return false
end

def process_image(img)
  # Fix the URL if we don't have the extension
  # but first, see if it's an album
  is_album = false
  full_url = "#{CONFIG[:imgur_base]}#{img}"
  if ( img.include? 'a/')
    is_album = true
    full_url = "#{CONFIG[:imgur_base]}#{img}/all"
  elsif ( !img.include? '.' )
    full_url = "#{CONFIG[:imgur_base]}download/#{img}"
  end

  if  ( is_album )
    # Grab the HTML, parse for
    # data-src="http://i.imgur.com/a65tps.jpg"
    # And create more urls..?
    return parse_album(full_url)
  else
    return [fetch_file(img,full_url)]
  end
end

def process_reddit_url(reddit_id)
  imgur_links = {}
  begin
    reddit_url = "#{CONFIG[:reddit_base]}#{reddit_id}"
    # Grab the frameset HTML
    page_data = ''
    open(reddit_url) { |remote_data|
      remote_data.each_line { |line|
        page_data << line
      }
    }

    # Scan the page data for the target frame link
    frame_id = ''
    page_data.scan(CONFIG[:reddit_frame_regex]).each { |match|
      frame_id = match[0].chomp
      log("Processing #{frame_id} from reddit frame #{reddit_url}")
    }

    # Find the title
    title = ''
    page_data.scan(CONFIG[:reddit_title_regex]).each { |match|
      title = match[0].chomp
      log("Found title \"#{title}\" from reddit frame #{reddit_url}")
    }

    if ( frame_id.empty? )
      log("Cannot find frame_id from #{reddit_url}")
      return imgur_links.keys
    end

    frame_url = "#{CONFIG[:reddit_frame_base]}#{frame_id}"
    # Grab the actual HTML
    page_data = ''
    open(frame_url) { |remote_data|
      remote_data.each_line { |line|
        page_data << line
      }
    }

    # Find the links!
    page_data.scan(CONFIG[:url_regex]).each { |match|
      imgur_links[match[0].chomp] = title
    }
  rescue => e
    log(e.message)
    e.backtrace.each {|l| log(l) }
    $imap.logout
    free_lock()
    exit
  end
  return imgur_links
end

def parse_album(full_url)
  files = []
  begin
    # Grab the HTML
    page_data = ''
    open(full_url) { |remote_data|
      remote_data.each_line { |line|
        page_data << line
      }
    }
    # Scan the page data
    page_data.scan(CONFIG[:album_url_regex]).each { |match|
      img = match[0].chomp
      # Remove the 's' before the extension. Ew.
      img.sub!(/s\./,'.')
      log("Processing #{img} from album #{full_url}")
      if ( !$processed_images[img] )
        files << process_image(img).first
      end
    }
  rescue => e
    log(e.message)
    e.backtrace.each {|l| log(l) }
    $imap.logout
    free_lock()
    exit
  end
  return files
end

def fetch_file(img,full_url)
  dir = "#{CONFIG[:image_dir]}#{img[0..2].split(//).join('/')}/".downcase.chomp
  file = "#{dir}#{img}".chomp

  # Create the directory if needed
  if ( !File::directory?(dir) )
    begin
    FileUtils.mkdir_p(dir)
    rescue => e
      log(e.message)
      e.backtrace.each {|l| log(l) }
      $imap.logout
      free_lock()
      exit
    end
  end

  content_type = ''
  new_file = ''
  if ( !File.file?(file) )
    begin
      log("Fetching #{full_url} to #{file}")
      File.open(file,'w') { |output_file|
        open(full_url) { |remote_data|
          content_type = remote_data.content_type
          # Always grab the extension from the content type? Probably a good idea...
          extension = MIME::Types[content_type].first.extensions.first
  	      if ( !img.include? '.' )
            new_file = "#{file}.#{extension}"
          else
            # Might want to check to see if the extension is already there...
            new_file = file.sub(File.extname(file),".#{extension}")
          end
          remote_data.each_line { |line|
            output_file << line
          }
        }
      }
    rescue => e
      log(e.message)
      e.backtrace.each {|l| log(l) }
      $imap.logout
      free_lock()
      exit
    end
  end

  # If we need to add an extension, do so
  if ( !file.eql?(new_file) )
    log("Moving #{file} to #{new_file}")
    FileUtils.mv(file,new_file)
  end

  file_data = {
    :name         => img,
    :path         => new_file,
    :content_type => content_type
  }
  return file_data
end

# Lock!
if ( !get_lock() )
  exit
end

# Connect to the mail server
begin
  $imap = Net::IMAP.new( CONFIG[:host], CONFIG[:port], CONFIG[:ssl] )
  $imap.login( CONFIG[:username], CONFIG[:password] )
rescue => e
  log(e.message)
  log(e.backtrace)
  $imap.logout
  free_lock()
  exit
end

# select the INBOX as the mailbox to work on
$imap.select('INBOX')

messages_to_archive = []
messages_to_send = []
$processed_images = {}

# retrieve all messages in the INBOX that
# are not marked as DELETED (archived in Gmail-speak)
$imap.search(['NOT', 'DELETED']).each do |message_id|
  # Grab the actual message
  msg = $imap.fetch(message_id,'RFC822')[0].attr['RFC822']
  mail = Mail.read_from_string(msg)

  # The new To: will be the email's reply_to or from address
  to_addr = mail.reply_to
  if ( to_addr.nil? or to_addr.empty? )
    to_addr = mail.from
  end
  if ( to_addr.nil? or to_addr.empty? )
    log("Could not find a valid from address, skipping")
    next
  end

  log("Checking #{mail.message_id} (#{to_addr})")
  # Look for imgur URLs
  found_urls = {}
  msg.scan(CONFIG[:url_regex]).each { |match|
    found_urls[match[0].chomp] = 'Could not find title'
  }

  # Look for reddit URLs and find the imgur links
  msg.scan(CONFIG[:reddit_id_regex]).each { |match|
    log("Found reddit URL, looking for imgur links")
    process_reddit_url(match[0].chomp).each { |url,title|
      found_urls[url] = title
    }
  }

  found_urls.each_key { |url|
    log("Processing #{mail.message_id} (#{url})")
    CONFIG[:url_file_regex].match(url)
    img = $1.chomp

    # See if we've dealt with this image before
    if ( !$processed_images[img] )
      file_paths = process_image(img)

      subject = "File from #{url} - #{found_urls[url]}"
      if ( file_paths.length > 1 )
        subject = "Files from #{url} - #{found_urls[url]}"
      end

      # Store the email data
      msg_data = {
        :to           => to_addr.first,
        :title        => found_urls[url],
        :subject      => subject,
        :orig_subject => mail.subject,
        :files        => file_paths,
        :message_id   => mail.message_id
      }

      messages_to_send << msg_data
    end

    # Mark the image as "done"
    $processed_images[img] = true
  }

  # Did we process the image? If so, archive the email
  if ( found_urls.length > 0 )
    log("Copying #{mail.message_id} to #{CONFIG[:processed_mailbox]}")

    # Copy the message to the processed mail box
    begin
       # create the mailbox, unless it already exists
       $imap.create(CONFIG[:processed_mailbox]) unless $imap.list('', CONFIG[:processed_mailbox])
    rescue Net::IMAP::NoResponseError => e
      log(e.message)
      e.backtrace.each {|l| log(l) }
      $imap.logout
      free_lock()
      exit
    end

    # copy the message to the proper mailbox/label
    $imap.copy(message_id, CONFIG[:processed_mailbox])

    messages_to_archive << message_id
  end
end

# Archive the original messages
$imap.store(messages_to_archive, "+FLAGS", [:Deleted]) unless messages_to_archive.empty?
$imap.logout

# Some cuteness
message_bodies = [
  'Love you!',
  'Hi Cutie!',
  'Hi Sweetie!',
  'Hi! *smooch*',
  'Wooo! *hug*',
  'Wooo!',
  '*smoooooOOOOOOoooooooch*!!!',
  '*smooch*',
  '*smooch* <3',
  '*smooch* ;)',
  '*hug*',
  '*hug* <3',
  '<3',
  '<3 <3',
  ';)',
  'Cutie!!',
  'Cutie! ;)',
  'You are the cutest!',
  'You are the cutest. *smooch*',
  'Sweetie! *smooch*',
  'Miss you!',
  'You\'re the best!',
  '@}-,-`-.',
  '<3 @}-,-`-. <3',
  '*dance*',
  'ZZZzzz.... *hug*',
  'Hello beautiful!'
  ]

# Messages based on the current month and day
d = DateTime.now
special_dates = {
  1   => {20 => [
    'Happy Anniversary!!',
    'I Love you lots!'
  ]},
  2   => {14 => [
    'Valentine\'s day kisses!',
    '<3 <3 <3 <3 *smooch* <3 <3 <3 <3'
  ]},
  11  => {28 => [
    'Happy Birthday!',
    'Birthdaaaaaaaay!'
  ]}
}

if ( !messages_to_send.empty? )
  # Connect to gmail and send the messages
  gmail = Gmail.new(CONFIG[:username], CONFIG[:password])
  messages_to_send.each { |msg|
    log("Sending reply for #{msg[:message_id]} to #{msg[:to]}")

    # The basics
    message_cute = message_bodies.sample
    # Check for a special day
    if ( special_dates.key? d.month and special_dates[d.month].key? d.day )
      message_cute = special_dates[e.month][e.day].sample
    end
    message_footer = "Requested by #{msg[:to]}, via email with subject \"#{msg[:orig_subject]}\""
    message_text = "#{message_cute}\n\nTitle: #{msg[:title]}\n#{message_footer}"
    message_html = "<h1>#{message_cute}</h1><br/><br/>Title: #{msg[:title]}<br/>#{message_footer}"

    # Create the message
    reply_mail = gmail.generate_message do
      to      msg[:to]
      from    'Imgur Helper <imgur@simianworks.net>'
      subject msg[:subject]

      text_part do
        body message_text
      end

      html_part do
        content_type 'text/html; charset=UTF-8'
        body message_html
      end
    end
    # Attach the files
    msg[:files].each() { |file|
      reply_mail.attachments[file[:name]] = {:mime_type => file[:content_type], :content => File.read(file[:path])}
    }
    # Go!
    reply_mail.deliver!
    log("Sent reply for #{msg[:message_id]}")
  }
  gmail.logout

  # Delete the saved files
  messages_to_send.each { |msg|
    msg[:files].each() { |file|
      if ( File.file?(file[:path]) )
        log("Removing #{file[:path]}")
        begin
          File.delete(file[:path])
        rescue => e
          log(e.message)
          e.backtrace.each {|l| log(l) }
        end
      end
    }
  }
end

free_lock()
