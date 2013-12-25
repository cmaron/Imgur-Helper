Imgur-Helper
============

A basic email parser that can be run to look for imgur links (and reddit "share" emails) and send back the images. Useful if imgur is blocked for you but email is not...

Use
---

This is a basic Ruby script that will check a given email address and process every email found in the inbox. Currently Gmail is supported in this, but it is feasible to re-work the code to handle any IMAP mail server (Gmail was just easier at the time).

The emails sent to the specific address are assumed to essentially have no subject with just be an imgur link in the body, like this:

![Example email send](http://i.imgur.com/iEEZQ0r.png?1 "Example email send")
 
After processing, an email will come back from the assigned email account with the image(s) attached.

![Example reply](http://i.imgur.com/EXtad7v.png?1 "Example reply")


This should also work with albums, and links shared directly from reddit via the "share" functionality. *It's likely the "share" piece needs to be updated…*

Installation
------------

### Requirements

#### Ruby
I have been running this in ruby 1.9.2p318, but anything beyond that revision should be fine. I have not tested this with Ruby 2.0.0

#### Ruby Gems
The following ruby gems should be installed. Newer versions are likely to be fine.

* mail (2.4.4)
* mime (0.1)
* mime-types (1.18)
* ruby-gmail (0.2.1)


### Setup
You will need a place to run the script, preferably a computer that will always be on and one where you can install ruby. 

There is one main configuration block at the top of the script. The two things you must change are the email address username and password. Look for `[USERNAME]` and `[PASSWORD]`:

```
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
```

Once installed, the script can be run at regular intervals to check for emails and send images. A basic crontab entry for this might be

```
* * * * * cd /home/imgur; /home/imgur/mail_parser.rb >> /home/imgur/parser.log 2>&1
```

Running every minute might get funky, as there is currently no logic to move emails that fail to process out of the inbox (see the TODO below).

TODO
----
### In no particular order…

* Cleanup and make sure things still work (the original version of this is old by now)
* Make sure all the imports are really needed. Work through an install as if someone did not have ruby
* Better handling of emails that cannot be parsed, perhaps move them to a "WTF" folder?
* Make sure the emails are visible on more email clients? Mainly tested with OS X
* Some way to cleanup the local image cache, either based on size, file age, or a combination of both. I am not sure it cleans up if the parsing/emailing fails.
* Update the version of ruby and the various ruby gems in use.
