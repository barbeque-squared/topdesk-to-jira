require 'daemons'

Daemons.run("#{File.dirname(__FILE__)}/topdesk2jira.rb")
