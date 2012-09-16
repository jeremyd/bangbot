require 'cinch'
require "cinch/plugins/identify"
require 'time'
require 'date'
# didja know ruby does json in 1.9.?!?  awesome.
require 'json'
require 'pg'
require 'pry'

module BangbotMethods

  def initialize(*args)
    super_result = super
    init_data
    super_result
  end

  #
  ## Simple Postgres JSON data storage
  #
  def create(table, hash_of_attributes)
    @@pg_conn.exec("insert into #{tablename}#{table}(json) values ('#{JSON::dump(hash_of_attributes)}') ")
  end

  def update(table, id, hash_of_attributes)
    @@pg_conn.exec("update #{tablename}#{table} set json = ('#{JSON::dump(hash_of_attributes)}') where id = #{id} ")
  end

  def delete(table, id)
    @@pg_conn.exec("delete from #{tablename}#{table} where id = #{id}")
  end

  def get(table, id)
    results = @@pg_conn.exec("select * from #{tablename}#{table} where id = #{id}")
    log("WARNING: there is more than one result for id: #{id}, num_tuples=#{results.num_tuples}") if results.num_tuples > 1
    parse_results(results).first
  end

  def read(table)
    results = @@pg_conn.exec("select * from #{tablename}#{table}")
    parse_results(results)
  end

  def parse_results(results)
    result_array = [] 
    results.each do |result|
      inject_id = JSON.parse(result["json"])
      inject_id["id"] = result["id"]
      result_array << inject_id
    end
    result_array
  end

  def create_pg_table(the_name)
    @@pg_conn.exec("create table #{the_name} (id bigserial primary key, json text)")
  end

  def find_or_create_table(the_name)
    table_finder = @@pg_conn.exec("SELECT table_name FROM information_schema.tables where table_name = '#{the_name}'")
    create_pg_table(the_name) if table_finder.none?
  end

  def init_data
    if defined?(@@pg_conn)
      # do nothing
      log("DATA CONNECTION: already initialized, re-using")
    else
      log("INITIALIZING DATA CONNECTION")
      @@pg_conn = PG.connect( dbname: "#{dbname}" )
      find_or_create_table("#{tablename}tasks")
      find_or_create_table("#{tablename}watches")
    end
  end

  def dbname
    config[:dbname]
  end

  def tablename
    config[:tablename]
  end

  def filter_text(text)
    # filter incoming text for weird chars that json doesn't like.
    text.gsub(/'/,"") #rubies json implementation doesn't appear to support single quote
  end

    # add #sometag <your message>
  def add(m, tag, tasktxt)
    create(:tasks, {"creator" => m.user.nick, 
                   "tag" => tag, 
                   "text" => filter_text(tasktxt), 
                   "bumped" => DateTime.now.to_s } )
    m.reply "Bang! task created."
  end

  def help_message(nick)
    help_message =<<EOF
#{nick}: thanks for asking!  Help follows:
list tasks:  list <string, regex>
add tasks:   add #<yourtag> <string>
ship tasks:  !<menu item # from the list>
EOF
  end

  #
  ## Any message directed at hellocomputer
  #
  def greeting(m, message)
    if message =~ /help/
      m.reply help_message(m.user.nick)
    else
      m.reply "#{m.user.nick}: Thanks for asking!  I did not recognize your question.  Try asking me for help."
    end
  end

  #
  ## List
  # support list <query> where the query field is tag or creator 
  def list(m, target)
    target.gsub!(/^\s+/,"") #remove leading whitespace
    results = []
    read(:tasks).each do |record|
      unless target.empty?
        target_regex = /#{target}/
        if record["tag"] =~ target_regex || record["creator"] =~ target_regex
          results << record
        end
      end
    end
    m.reply "==== found #{results.length} results. ===="
    # sort by last bumped
    sorted = results.sort do |x,y| 
      xd = DateTime.iso8601(x["bumped"])  
      yd = DateTime.iso8601(y["bumped"]) 
      yd <=> xd
    end
    sorted.each_with_index do |r, ind|
      m.reply "!#{r["id"]} ##{r["tag"]} '#{r["text"]}'; created by #{r["creator"]}"
    end
    m.reply "==== **** ===="
  end

  #
  ## Bump a task
  #
  def bump(m, ind)
    found_attribs = get(:tasks, ind)
    m.reply "task not found.  please relist and try again" && return unless found_attribs
    found_attribs["bumped"] =  DateTime.now.to_s
    update(:tasks, ind, found_attribs)
    bot.channels.each do |chan|
      m.reply "bumping on #{chan}.. Bang!"
      chan.msg "Bang! ##{found_attribs["tag"]} - #{m.user.nick} &&& BUMPED &&& '#{found_attribs["text"]}'; created by #{found_attribs["creator"]}"
    end
  end

  #
  ## Ship a task
  #
  def shipit(m, ind)
    found_attribs = get(:tasks, ind)
    if found_attribs
      bot.channels.each do |chan|
        m.reply "telling the #{chan} world about your success. Bang!"
        chan.msg "Bang! ##{found_attribs["tag"]} - #{m.user.nick} |-o-| (-o-) |-o-| SHIPPED '#{found_attribs["text"]}'; created by #{found_attribs["creator"]}"
      end
      delete(:tasks, ind)
    else
      m.reply "item not found; please relist and try again"
    end
  end

  #
  ## Delete a task (silently)
  #
  def silent_delete(m, ind)
    found_attribs = get(:tasks, ind)
    m.reply "task not found.  please relist and try again" && return unless found_attribs
    m.reply "silently deleting the task.  Bang!"
    delete(:tasks, ind)
  end

  #
  ## Smartly watch the gerrit stream from a different channel
  #
  def watch_for_me(m, chan, pass, name)
    create(:watches, { "chan" => "##{chan}", "chan_pass" => pass, "watch_pattern" => name, "created_by" => m.user.nick })
    refresh_watches
    m.reply "gerrit notification enabled."
  end

  #returns the gerrit changeid based on the message that was parsed
  def glean_gerrit_changeid(message)
    message =~ /.+?codereview\/(\d+)/
    return $1
  end

  def watch_action(m, watch)
    changeid = glean_gerrit_changeid(m.message)
    coderevwatch = "codereview\/#{changeid}$"
    already_exists = false
    read(:watches).each do |w|
      if w["watch_pattern"] == coderevwatch
        already_exists = true
      end
    end
    unless already_exists
      create(:watches, { "chan" => "##{watch['chan']}", "chan_pass" => watch['chan_pass'], "watch_pattern" => coderevwatch, "created_by" => watch['created_by'] })
      refresh_watches
    end
    if watch["watch_pattern"] =~ /^codereview/ && already_exists
      found_nick = User(watch["created_by"])
      unless found_nick
        log "ERROR: something went wrong or user is offline, couldn't find a user to notify for #{watch['created_by']}"
        return
      end
      found_nick.msg "Matched: #{m.message}"
    end
  end

  def refresh_watches(*args)
    read(:watches).each do |watch|
      bot.join(watch["chan"], watch["chan_pass"]) unless bot.channels.include?(watch["chan"])
      bot.on(:message, /#{watch['watch_pattern']}/, watch, self) do |m, watch, obj|
        obj.watch_action(m, watch)
      end
    end
  end

end

class Bangbot
  include Cinch::Plugin
  include BangbotMethods

  listen_to :connect, method: :refresh_watches

  #
  ## Routing of matches
  #
  match /^add #([\w,\-,_]+) (.*)$/, :method => :add, :use_prefix => false, :use_suffix => false
  match /^^bangbot(.*)/, :method => :greeting, :use_prefix => false, :use_suffix => false
  match /^hellocomputer(.*)/, :method => :greeting, :use_prefix => false, :use_suffix => false
  match /^computer(.*)/, :method => :greeting, :use_prefix => false, :use_suffix => false
  match /^hello computer(.*)/, :method => :greeting, :use_prefix => false, :use_suffix => false
  match /^list(.*)/, :method => :list, :use_prefix => false, :use_suffix => false
  match /^bump (\d+)/, :method => :bump, :use_prefix => false, :use_suffix => false
  match /^delete (\d+)/, :method => :silent_delete, :use_prefix => false, :use_suffix => false
  match /^!(\d+)/, :method => :shipit, :use_prefix => false, :use_suffix => false
  # gerrit watch #chan <password> name match
  match /^gerrit watch #([\w,\-,_]+) (.+?) (.+)/, :method => :watch_for_me, :use_prefix => false, :use_suffix => false
end
