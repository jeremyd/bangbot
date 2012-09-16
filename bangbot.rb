require 'cinch'
require "cinch/plugins/identify"
require 'time'
require 'date'
# didja know ruby does json in 1.9.?!?  awesome.
require 'json'

#
## Simple JSON datastorage (tm)
# Things in @@datastore are flushed to .json file with save_data()
# TODO: this likely isn't very threadsafe.
MY_CONFIG = File.join(File.dirname(__FILE__), "bangbot.storage.json")

def save_data
  File.open(MY_CONFIG, "w") { |f| f.write(JSON::dump(@@datastore)) }
end

if File.exists?(MY_CONFIG)
  if @@datastore = JSON::parse(IO.read(MY_CONFIG))
    puts "successfully loaded datastore from #{MY_CONFIG}"
  else
    puts "FATAL: unable to load #{MY_CONFIG}.. File exists but is corrupt!"
  end
else
  puts "datastore does not exist in #{MY_CONFIG}.. creating new."
  # bangtasks: an array of hashes; one hash per task
  # usermenus: hash of last menu displayed per user;
  @@datastore = {
    "bangtasks" => [],
    "usermenus" => {}
  }
end

bot = Cinch::Bot.new do
  configure do |c|
    c.realname = "Computer"
    c.user = "Computer"
    c.nicks = ["hellocomputer", "hellocomputer_", "hellocomputer__"]
    c.server = "irc.freenode.net"
    c.channels = ["#rubyonlinux"]
    c.plugins.plugins = [Cinch::Plugins::Identify]
    c.plugins.options[Cinch::Plugins::Identify] = {
      :username => "hellocomputer",
      :password => "somekindapizza",
      :type     => :nickserv,
    }
  end

  #def greeting(message)
  #  if message =~ /help/
  #    m.reply "#{m.user.nick}: thanks for asking!  Help follows:"
  #    m.reply "list tasks:  list <string, regex>"
  #    m.reply "add tasks:   add #<yourtag> <string>"
  #    m.reply "ship tasks:  !<menu item # from the list>"
  #  else
  #    m.reply "#{m.user.nick}: Thanks for asking!  I did not recognize your question.  Try asking me for help."
  #  end
  #end

  # add #sometag <your message>
  on :message, /^add #(\w+) (.*)$/ do |m, tag, tasktxt|
    #m.reply "Hello, #{m.user.nick}"

    synchronize(@@datastore) do
      @@datastore["bangtasks"] << {"creator" => m.user.nick, 
                                   "tag" => tag, 
                                   "text" => tasktxt, 
                                   "bumped" => DateTime.now.to_s }
      save_data 
    end
    m.reply "Bang! task created."
  end

  #
  ## Any message directed at hellocomputer
  #
  on :message, /^hellocomputer(.*)/ do |m, message|
    #greeting(message)
  end

  on :message, /^computer(.*)/ do |m, message|
    #greeting(message)
  end

  on :message, /^hello computer(.*)/ do |m, message|
    #greeting(message)
  end

  #
  ## List
  # support list <query> where the query field is tag or creator 
  on :message, /list(.*)/ do |m, target|
    target.gsub!(/^\s+/,"") #remove leading whitespace
    results = []
    @@datastore["bangtasks"].each do |record|
      unless target.empty?
        target_regex = /#{target}/
        if record["tag"] =~ target_regex || record["creator"] =~ target_regex
          results << record
        end
      end
    end
    m.reply "found #{results.length} results."
    # sort by last bumped
    sorted = results.sort do |x,y| 
      xd = DateTime.iso8601(x["bumped"])  
      yd = DateTime.iso8601(y["bumped"]) 
      yd <=> xd
    end
    sorted.each_with_index do |r, ind|
      m.reply "#{ind}) ##{r["tag"]} '#{r["text"]}'; created by #{r["creator"]}"
    end
    @@datastore["usermenus"][m.user.nick] = sorted
    save_data
  end

  #
  ## Bump a task
  #
  on :message, /bump (\d+)/ do |m, ind|
    target = @@datastore["usermenus"][m.user.nick][ind.to_i]
    synchronize(@@datastore) do
      @@datastore["bangtasks"].select { |entry| entry == target }.first["bumped"] = DateTime.now.to_s
    end
    save_data
    m.reply "bumping.. Bang!"
    bot.channels.each do |chan|
      chan.msg "Bang! ##{target["tag"]}\n#{m.user.nick} bumped '#{target["text"]}'; created by #{target["creator"]}"
    end
  end

  on :message, /!(\d+)/ do |m, ind|
    bot.channels.each do |chan|
      target = @@datastore["usermenus"][m.user.nick][ind.to_i]
      if target
        m.reply "telling the world about your success. bang!"
        chan.msg "Bang! ##{target["tag"]}\n#{m.user.nick} shipped  '#{target["text"]}'; created by #{target["creator"]}"
        synchronize(@@datastore) do
          # delete the task
          @@datastore["bangtasks"].reject! { |entry| entry == target }
          # invalidate previous menu
          @@datastore["usermenus"].reject! { |nick| nick == m.user.nick }
          save_data
        end
      else
        m.reply "sorry, menu item was stale, please relist and try again"
      end
    end
  end
end

bot.start
