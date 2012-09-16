require 'minitest/spec'
require 'minitest/autorun'
require 'minitest/mock'
require 'bangbot'
require 'tmpdir'

class BangbotTest
  include BangbotMethods

  def initialize
    init_data
  end

  def log(*args)
    raise "ERROR: detected an error string in the log!  This should be investigated:  #{args.inspect}" if args.to_s =~ /ERROR/
    puts args.inspect
  end

  def test_bot_verify
    @mock_chan.verify
    @mock_bot.verify
  end

# Had to provide/mock the following methods.
# Replaces cinch-plugin functions used in BangbotMethods
  def bot
    @mock_chan = MiniTest::Mock.new
    @mock_chan.expect(:msg, nil, [String])
    @mock_bot = MiniTest::Mock.new
    @mock_bot.expect(:channels, [@mock_chan])
  end

  def synchronize(*args, &block)
    @mutex ||= Mutex.new
    @mutex.synchronize(&block)
  end

  def reset_database
# reset the test database prior to each test.
    alltasks = read(:tasks)
    alltasks.each do |task|
      delete(:tasks, task["id"])
    end
  end

  def config
    {:dbname => "bangbot", :tablename => "test_jsonz"}
  end
end

describe BangbotTest do

  before do
    # Setup the common set of mocks.
    @mock_user = MiniTest::Mock.new
    @mock_m = MiniTest::Mock.new

    # Use separate temporary config.  Wipe it each time.
    @bangbot_tmp_dir = File.join(File.dirname(__FILE__), "..", "tmp")
    @bot = BangbotTest.new()
    @bot.init_data
    @bot.reset_database
    @bot.init_data
  end

  #common pattern, m.user.nick
  def expect_user_nick
    @mock_user.expect(:nick, "testuser")
    @mock_m.expect(:user, @mock_user)
  end

  def expect_add_task
    expect_user_nick
    @mock_m.expect(:reply, nil, ["Bang! task created."])
  end
  
  def expect_list_tasks
    @mock_m.expect(:reply, nil, ["==== found 1 results. ===="])
  end

  def verify_all
    @mock_user.verify
    @mock_m.verify
  end

  it "displays generic greeting message" do
    expect_user_nick
    @mock_m.expect(:reply, nil, ["testuser: Thanks for asking!  I did not recognize your question.  Try asking me for help."])
    @bot.greeting(@mock_m, "hello bot world")
    verify_all
  end

  it "displays the help when asked" do
    expect_user_nick
    @mock_m.expect(:reply, nil, [@bot.help_message("testuser")])
    @bot.greeting(@mock_m, "help")
    verify_all
  end

  it "adds a task" do
    expect_add_task
    @bot.add(@mock_m, "test", "testtask")
    verify_all
  end

  it "lists the tasks" do
    expect_add_task
    expect_list_tasks
    @bot.add(@mock_m, "tag", "testtask")
    @bot.list(@mock_m, "tag")
    verify_all
  end

  it "deletes the task" do
    expect_add_task
    @bot.add(@mock_m, "tag", "testtask")
    @bot.silent_delete(@mock_m, "0")
    verify_all
  end

  it "ships the task" do
    expect_add_task
    @bot.add(@mock_m, "tag", "testtask")
    @bot.shipit(@mock_m, "0")
    verify_all
  end

end
