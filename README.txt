Bangbot uses Ruby, Cinch, and Postgres.

Installation Instructions used for Ruby 1.9:

gem install cinch cinch-identify pg pry --no-rdoc --nori
git clone https://github.com/jeremyd/bangbot.git
cd bangbot
cp config/bangbot.conf.rb.example config/bangbot.conf.rb
vim bangbot.conf.rb # save your config

!Create the postgres database and credentials you specified!

rake test # YES there are tests.  You can run them and they will pass!
ruby start.rb
