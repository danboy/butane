#!/usr/bin/env ruby
require 'rubygems'
require 'tinder'
require 'yaml'

def notify(header,msg,options = {})
  `notify-send #{options[:img]} #{options[:delay]} '#{header}' '#{msg}'`
end

def monitor_room(room, config = {})
  sticky = config[:sticky]
  ignore = config[:ignore]

  room_name = room.name.gsub /"/, '' # Get rid of any dquotes since we use 'em to delimit person
  last_message_id = 0
  room.listen do |m|
    # Ignore any pings from campfire to determine if I'm still
    # here
    next if m[:person].strip.empty?  # Ignore anything from a nil / empty person

    next if m[:id].to_i <= last_message_id
    last_message_id = m[:id].to_i

    delay = "" # in milliseconds (time to display the notification)


    # If we're to monitor something in particular in this room, set the
    # delay notification to zero which will leave the message up until
    # clicked away.
    if sticky
      delay = '-t 0' if m[:message] =~ /#{sticky}/i
    end

    if ignore
      next if m[:message] =~ /#{ignore}/
    end

    img_opt = "-i #{config[:image]}" if config[:image]

    person = m[:person].gsub /"/, ''  # Get rid of any dquotes since we use 'em to delimit person

    msg = m[:message].dup
    msg.gsub! /'/, ''       # Get rid of single quotes since we use 'em to delimit msg
    msg.gsub! '\u003E', '>'
    msg.gsub! '\u003C', '<'
    msg.gsub! '\u0026', '&'
    msg.gsub! '\"', '"'
    msg.gsub! '&hellip;', '...'   # notify-send don't like this

    # And let's remove all but the href attribute in any anchors
    # in the msg.  Assumes that in href=stuff, stuff has no whitespace.

    msg.gsub! /<a[^>]+(href=[^\s]+)[^>]*>/, '<a \1>'
    notify(m[:person],msg,{:img => img_opt, :delay => delay})

  end
end

config = YAML::load_file("#{ENV['HOME']}/.butanerc")
account_names = config.keys

threads = []
account_names.each do |account_name|
  rooms = config[account_name][:rooms]
  account_img = config[account_name][:image]
  if rooms && rooms.size > 0
    campfire = Tinder::Campfire.new account_name, :ssl => config[account_name][:ssl]
    begin
      campfire.login config[account_name][:login], config[account_name][:password]
    rescue Tinder::Error => e
      puts "Problem logging in to #{account_name} : #{e.message}"
      next
    end
    puts "Connected to #{account_name}"

    # Start up a thread for each room we are going to monitor
    rooms.keys.each do |room_name|
      notify("  Looking for room ","#{room_name} ... ")
      room = campfire.find_room_by_name room_name
      if room
        room_cfg = rooms[room_name] || {}
        room_cfg[:image] ||= account_img
        puts "  got it and monitoring."
        img_opt = "-i #{config[account_name][:image]}" if config[account_name][:image]
        notify(room_name,"is now being moitored",{:img => img_opt})
        threads << Thread.new(room, room_cfg) do |r, cfg|
          monitor_room(r, cfg)
        end
      else
        puts "  hmmm, didn't find it."
        notify(room_name,"failed to connect",{:img => img_opt})
      end
    end
  end
end

threads.each { |t| t.join }
