FROM debian:8.2

LABEL com.example.app.name="gitlab"
LABEL com.example.app.version="7.14.1"

ENV DEBIAN_FRONTEND noninteractive

# ARG ${version}

RUN apt-get update && \
    apt-get install -y curl vim net-tools procps

RUN apt-get install -y debian-archive-keyring apt-transport-https openssh-server

# COPY gitlab-script.deb.sh /script.deb.sh
# RUN bash /script.deb.sh

# RUN apt-key adv --keyserver ha.pool.sks-keyservers.net --recv-keys 14219A96E15E78F4
# COPY gitlab.list /etc/apt/sources.list.d/
#RUN apt-get update && \
#    apt-get install gitlab-ce=8.2.0-ce.0

# COPY deb/gitlab-ce_7.14.1-ce.0_amd64.deb /
# RUN dpkg -i /gitlab-ce_7.14.1-ce.0_amd64.deb


# https://github.com/gitlabhq/gitlabhq/blob/master/doc/install/installation.md

# ################ #
# 1. Dependencies  #
# ################ #
RUN apt-get update -y
RUN apt-get upgrade -y
RUN apt-get install sudo -y

# Install vim and set as default editor
RUN sudo apt-get install -y vim
RUN sudo update-alternatives --set editor /usr/bin/vim.basic

# Install the required packages (needed to compile Ruby and native extensions to Ruby gems)
RUN sudo apt-get install -y build-essential zlib1g-dev libyaml-dev libssl-dev libgdbm-dev libreadline-dev libncurses5-dev libffi-dev curl openssh-server redis-server checkinstall libxml2-dev libxslt-dev libcurl4-openssl-dev libicu-dev logrotate python-docutils pkg-config cmake nodejs

#If you want to use Kerberos for user authentication
RUN sudo apt-get install -y libkrb5-dev

# Install Git
RUN sudo apt-get install -y git-core

# Make sure Git is version 1.7.10 or higher, for example 1.7.12 or 2.0.0
RUN git --version

# In order to receive mail notifications
#RUN debconf-set-selections <<< "postfix postfix/mailname string localhost"
#RUN debconf-set-selections <<< "postfix postfix/main_mailer_type string 'Internet Site'"
#RUN sudo apt-get install -y postfix


# ######## #
# 2. Ruby  #
# ######## #
# Remove the old Ruby 1.8 if present
RUN sudo apt-get remove ruby1.8

# Download Ruby and compile it:
RUN mkdir /tmp/ruby
WORKDIR /tmp/ruby
RUN curl -L --progress http://cache.ruby-lang.org/pub/ruby/2.1/ruby-2.1.6.tar.gz | tar xz
WORKDIR ruby-2.1.6
RUN ./configure --disable-install-rdoc
RUN make
RUN sudo make install

# Instal bundler
RUN sudo gem install bundler


# ######## #
# 3. Users #
# ######## #
# Create a git user for GitLab:
RUN sudo adduser --disabled-login --gecos 'GitLab' git


# ######## #
# 4. DB    #
# ######## #
# Install the database packages
RUN sudo apt-get install -y mysql-client libmysqlclient-dev

# MySQL only:
# -- RUN sudo -u git cp config/database.yml.mysql config/database.yml

# MySQL and remote PostgreSQL only:
# Update username/password in config/database.yml.
# You only need to adapt the production settings (first part).
# If you followed the database guide then please do as follows:
# Change 'secure password' with the value you have given to $password
# You can keep the double quotes around the password
# sudo -u git -H editor config/database.yml

# PostgreSQL and MySQL:
# Make config/database.yml readable to git only
# -- RUN sudo -u git -H chmod o-rwx config/database.yml


# ######## #
# 5. Regis #
# ######## #
RUN sudo apt-get install redis-server

# Configure redis to use sockets
RUN sudo cp /etc/redis/redis.conf /etc/redis/redis.conf.orig

# Install sed
RUN apt-get install -y sed

# Disable Redis listening on TCP by setting 'port' to 0
RUN sed 's/^port .*/port 0/' /etc/redis/redis.conf.orig | sudo tee /etc/redis/redis.conf

# Enable Redis socket for default Debian / Ubuntu path
RUN echo 'unixsocket /var/run/redis/redis.sock' | sudo tee -a /etc/redis/redis.conf
# Grant permission to the socket to all members of the redis group
RUN echo 'unixsocketperm 770' | sudo tee -a /etc/redis/redis.conf

# Create the directory which contains the socket
RUN mkdir /var/run/redis
RUN chown redis:redis /var/run/redis
RUN chmod 755 /var/run/redis

# Persist the directory which contains the socket, if applicable
# if [ -d /etc/tmpfiles.d ]; then
RUN echo 'd  /var/run/redis  0755  redis  redis  10d  -' | sudo tee -a /etc/tmpfiles.d/redis.conf
# fi

# Activate the changes to redis.conf
RUN sudo service redis-server restart

# Add git to the redis group
RUN sudo usermod -aG redis git


# ######## #
# 6. Gitlab #
# ######## #
# We'll install GitLab into home directory of the user "git"
WORKDIR /home/git

# Clone GitLab repositoy
RUN sudo -u git -H git clone https://gitlab.com/gitlab-org/gitlab-ce.git -b 7-14-stable gitlab
RUN sudo -u git -H git checkout 481c966

# Go to GitLab installation folder
WORKDIR /home/git/gitlab

# Copy the example GitLab config
# sudo -u git -H cp config/gitlab.yml.example config/gitlab.yml

# Update GitLab config file, follow the directions at top of file
# sudo -u git -H editor config/gitlab.yml

# Make sure GitLab can write to the log/ and tmp/ directories
RUN sudo chown -R git log/
RUN sudo chown -R git tmp/
RUN sudo chmod -R u+rwX,go-w log/
RUN sudo chmod -R u+rwX tmp/

# Create directory for satellites
RUN sudo -u git -H mkdir /home/git/gitlab-satellites
RUN sudo chmod u+rwx,g=rx,o-rwx /home/git/gitlab-satellites

# Make sure GitLab can write to the tmp/pids/ and tmp/sockets/ directories
RUN sudo chmod -R u+rwX tmp/pids/
RUN sudo chmod -R u+rwX tmp/sockets/

# Make sure GitLab can write to the public/uploads/ directory
RUN sudo chmod -R u+rwX  public/uploads

# Copy the example Unicorn config
# sudo -u git -H cp config/unicorn.rb.example config/unicorn.rb

# Find number of cores
RUN nproc

# Enable cluster mode if you expect to have a high load instance
# Ex. change amount of workers to 3 for 2GB RAM server
# Set the number of workers to at least the number of cores
# sudo -u git -H editor config/unicorn.rb

# Copy the example Rack attack config
# sudo -u git -H cp config/initializers/rack_attack.rb.example config/initializers/rack_attack.rb

# Configure Git global settings for git user, used when editing via web editor
RUN sudo -u git -H git config --global core.autocrlf input

# Configure Redis connection settings
# sudo -u git -H cp config/resque.yml.example config/resque.yml

# Change the Redis socket path if you are not using the default Debian / Ubuntu configuration
# sudo -u git -H editor config/resque.yml


# ################ #
# Install Gems     #
###################
# Or if you use MySQL (note, the option says "without ... postgres")
RUN sudo -u git -H bundle install --deployment --without development test postgres aws


# #################### #
# Install Gitlab Shell #
# #################### #
# Run the installation task for gitlab-shell (replace `REDIS_URL` if needed):
RUN sudo -u git -H bundle exec rake gitlab:shell:install[v2.6.5] REDIS_URL=unix:/var/run/redis/redis.sock RAILS_ENV=production

# By default, the gitlab-shell config is generated from your main GitLab config.
# You can review (and modify) the gitlab-shell config as follows:
# sudo -u git -H editor /home/git/gitlab-shell/config.yml


# ########################## #
# Initialize Database        #
# ########################## #
# sudo -u git -H bundle exec rake gitlab:setup RAILS_ENV=production


# ########################### #
# Install Init Script         #
# ########################### #
# -- RUN sudo cp lib/support/init.d/gitlab /etc/init.d/gitlab

# And if you are installing with a non-default folder or user copy and edit the defaults file:
# -- RUN sudo cp lib/support/init.d/gitlab.default.example /etc/default/gitlab

# Make GitLab start on boot:
# -- RUN sudo update-rc.d gitlab defaults 21


# ############################# #
# Setup Logrotate               #
# ############################# #
# -- RUN sudo cp lib/support/logrotate/gitlab /etc/logrotate.d/gitlab

#
# Check Application Status
#
# Check if GitLab and its environment are configured correctly:
RUN sudo -u git -H bundle exec rake gitlab:env:info RAILS_ENV=production

#
# Compile Assets
#
RUN sudo -u git -H bundle exec rake assets:precompile RAILS_ENV=production

#
# Start Your GitLab Instance
#
# sudo service gitlab start


#
# 7. Nginx
#
# -- RUN sudo apt-get install -y nginx

# -- RUN sudo cp lib/support/nginx/gitlab /etc/nginx/sites-available/gitlab
# -- RUN sudo ln -s /etc/nginx/sites-available/gitlab /etc/nginx/sites-enabled/gitlab

# Make sure to edit the config file to match your setup:

# Change YOUR_SERVER_FQDN to the fully-qualified
# domain name of your host serving GitLab.
# If using Ubuntu default nginx install:
# either remove the default_server from the listen line
# or else rm -f /etc/sites-enabled/default
# sudo editor /etc/nginx/sites-available/gitlab

# Test Configuration
#
# Validate your gitlab or gitlab-ssl Nginx config file with the following command:
#
# -- RUN sudo nginx -t

# Restart
# sudo service nginx restart

# Double-check Application Status
#
# To make sure you didn't miss anything run a more thorough check with:
RUN sudo -u git -H bundle exec rake gitlab:check RAILS_ENV=production

# Initial Login
# root
# 5iveL!fe
