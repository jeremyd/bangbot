require_relative "lib/bangbot"

# Load the configuation
require_relative "config/bangbot.conf.rb"
include BangbotConf
options = get_config

# Start the bot
bot = Cinch::Bot.new do
  configure do |c|
    c.realname = options[:realname]
    c.user = options[:user]
    c.nicks = [ options[:nickname], "#{options[:nickname]}_"]
    c.server = options[:server]
    c.channels = options[:channels]
    c.plugins.options[Bangbot] = {
        :dbname => options[:dbname],
        :tablename => options[:tablename]
    }
    if options[:nickservpass]
      c.plugins.plugins = [Bangbot, Cinch::Plugins::Identify]
      c.plugins.options[Cinch::Plugins::Identify] = {
        :username => options[:nickname],
        :password => options[:nickservpass],
        :type     => :nickserv,
      }
    else
      c.plugins.plugins = [Bangbot]
    end
  end
end
bot.start
