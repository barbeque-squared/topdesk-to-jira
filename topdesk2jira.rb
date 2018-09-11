# otherwise nothing works if you run it as a daemon
Dir.chdir File.dirname(__FILE__)

require 'dotenv'
Dotenv.load
require 'jira-ruby'
require 'active_record'
require 'tmpdir'
#~ require 'pp'
require_relative 'app/modules/topdesk'
require_relative 'app/models/item'

class TopdeskToJira
  def initialize
    db_config = YAML::load(File.open("#{File.dirname(__FILE__)}/config/database.yml"))[ENV['env']]
    ActiveRecord::Base.establish_connection(db_config)
    
    topdesk_options = {
      :site => ENV['TOPDESK_LOCATION'],
      :username => ENV['TOPDESK_USERNAME'],
      :password => ENV['TOPDESK_PASSWORD']
    }
    @topdesk = Topdesk::Client.new(topdesk_options)
    
    jira_options = {
      :site => ENV['JIRA_LOCATION'],
      :username => ENV['JIRA_USERNAME'],
      :password => ENV['JIRA_PASSWORD'],
      :auth_type => :basic,
      :use_ssl => false,
      #~ :http_debug => true,
      :context_path => ''
    }
    @jira = JIRA::Client.new(jira_options)
    
    @jira_project_key = ENV['JIRA_PROJECT_KEY']
    @jira_external_reference_field = ENV['JIRA_EXTERNAL_REFERENCE_FIELD']
  end
  
  def run
    incidents = @topdesk.incidents
    
    # new / updated
    incidents.each do |i|
      item = Item.find_by! topdesk_reference: i.number rescue createInJira(i)
      if i.modificationDate > item.updated_at
        # get progresstrail and do updates
        @topdesk.incident_progresstrail(i.id).reverse!.delete_if {|pt| pt.entryDate <= item.updated_at }.each do |pt|
          handleProgressTrailItem(pt, item.jira_reference)
        end
        item.updated_at = i.modificationDate
        item.save
      end
    end
    
    # done
    incident_numbers = incidents.map {|i| i.number}
    Item.where(closed_in_topdesk: false).each do |i|
      if not incident_numbers.include? i.topdesk_reference
        addGenericComment('Auto comment: no longer in Topdesk', i.jira_reference)
        i.closed_in_topdesk = true
        i.save
      end
    end
  end
  
  private
  
  def createInJira(incident)
    item = Item.new
    item.topdesk_reference = incident.number
    item.created_at = incident.callDate
    item.updated_at = incident.callDate
    
    # incident already exists in jira, just place a comment for now
    if not incident.externalNumber.empty? and incident.externalNumber.start_with? @jira_project_key+'-'
      issue = @jira.Issue.find(incident.externalNumber)
      item.jira_reference = issue.key
      # @todo: you'll probably want to have the number in the summary somewhere
      # @todo: fill in the @jira_external_reference_field in jira
      addGenericComment("Upgraded to Topdesk issue: #{incident.number}\n\n"+getDescription(incident), issue.key)
    else
      # new
      # @todo: probably do something with (configurable) issue types here
      options = {
        fields: {
          project: {key: @jira_project_key},
          summary: "#{incident.number} #{incident.briefDescription}",
          # 'Task' is the hardcoded issue type for now because it almost universally exists
          issuetype: {name: 'Task'},
          description: getDescription(incident)
          #duedate: incident.targetDate
        }
      }
      options['fields'][@jira_external_reference_field] = incident.number
      issue = @jira.Issue.build
      issue.save(options)
      item.jira_reference = issue.key
    end
    item.save
    item
  end
  
  def handleProgressTrailItem(pt, key)
    pth = pt.to_h
    if pth.key?(:fileName)
      addAttachment(pt, key)
    elsif pth.key?(:memoText)
      addComment(pt, key)
    elsif pth.key?(:sender)
      addEmail(pt, key)
    else
      raise "Unrecognized progresstrail element: #{pt}"
    end
  end
  
  def addAttachment(pt, key)
    # attachments might not always have an author
    text = "Topdesk attachment @ #{pt.entryDate}"
    if pt.size > 5_000_000_000 # 5 MB
      text += "\nFilename: #{pt.fileName}"
      text += "\n(Not attached because it's too big for JIRA!)"
    else
      Dir.mktmpdir {|dir|
        file = File.new(dir + File::SEPARATOR + pt.fileName, 'w+')
        # download attachment
        file.write @topdesk.rawUri(pt.downloadUrl).body
        attachment = @jira.Issue.find(key).attachments.build
        attachment.save!({'file' => file.path})
      }
      text += "\nFilename: [^#{pt.fileName}]"
    end
    addGenericComment(text, key)
  end
  
  def addComment(pt, key)
    text = "Topdesk comment: #{getName pt} @ #{pt.entryDate}\n#{pt.memoText.gsub('<br/>', "\n")}"
    addGenericComment(text, key)
  end
  
  def addEmail(pt, key)
    text = "Topdesk email: #{getName pt} @ #{pt.entryDate}\nSubject: #{pt.title}"
    addGenericComment(text, key)
  end
  
  def addGenericComment(text, key)
    comment = @jira.Issue.find(key).comments.build
    comment.save!(:body => text)
  end
  
  def getDescription(incident)
    res = []
    
    # @todo: this needs to be better configurable for i18n
    res.push "First/Second line: #{incident.status}"
    res.push "Category: #{incident.category.name}" if not incident.category.nil?
    res.push "Subcategory: #{incident.subcategory.name}" if not incident.subcategory.nil?
    res.push "Type: #{incident.callType.name}" if not incident.callType.nil?
    res.push "Object: #{incident.object.name}" if not incident.object.nil?
    res.push ''
    res.push "Impact: #{incident.impact.name}" if not incident.impact.nil?
    res.push "Urgency: #{incident.urgency.name}" if not incident.urgency.nil?
    res.push "Priority: #{incident.priority.name}" if not incident.priority.nil?
    res.push "Duration: #{incident.duration.name}" if not incident.duration.nil?
    res.push "Target date: #{incident.targetDate}" if not incident.targetDate.nil?
    res.push ''
    res.push "Request: #{incident.request}"
    
    res.join "\n"
  end
  
  def getName(pt)
    pth = pt.to_h
    if pth.key?(:operator) and not pt.operator.nil?
      pt.operator.name
    elsif pth.key?(:person) and not pt.person.nil?
      pt.person.name
    elsif pth.key?(:user) and not pt.user.nil?
      pt.user.name
    elsif pth.key?(:sender) and not pt.sender.nil?
      # some really old emails only
      pt.sender
    else
      raise "Cannot determine author of: #{pt}"
    end
  end
end

h = TopdeskToJira.new
loop do
  h.run
  #~ exit
  sleep 30
end
