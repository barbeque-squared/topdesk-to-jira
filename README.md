# Topdesk To Jira
Provides a way to duplicate Topdesk issues to Jira.
Advantages:
* No dependency on Topdesk plugins
* No dependency on Jira plugins

## Prequisites
You'll need the following things to get started:
* A Topdesk user that has API permissions. The API permissions can (should!) be readonly for this user.
* A Jira account that can create issues, comment on issues and place attachments on issues for your chosen Jira project.

## Setup
You'll want to create a `.env` file in the same directory as this readme that looks as follows:

```ruby
# Do not ever put this file under version control
# possible environments: development, production
env=development

# Topdesk configuration
TOPDESK_LOCATION=https://some.topdesk.net
TOPDESK_USERNAME=sometopdeskusername
# It's probably possible to use App passwords from Topdesk instead, but permissions are strange
TOPDESK_PASSWORD=sometopdeskpassword

# Jira configuration
JIRA_LOCATION=http://somejiraurl:8080/
JIRA_USERNAME=somejirausername
JIRA_PASSWORD=somejirapassword
JIRA_PROJECT_KEY=somejiraproject
JIRA_EXTERNAL_REFERENCE_FIELD=somejirafield
```

Use an Element Inspector or the JIRA API to get the field in which you want to place the Topdesk references (e.g. External Reference) because it usually has a name like `custom_field_10###`.

## Installation
`bundle install`
`bundle exec rake db:reset`

## Running the program
The default start command is `bundle exec ruby topdesk2jira.service.rb start`.
The program behaves like a daemon by default.
There is a control script which accepts one parameter: `start`, `stop`, `status`, `restart` or `run`.
The first four fork the program, the last one keeps the program open in your shell (for debugging).

## Known issues
There are some issues that still need to be worked out:
* The Topdesk API will only return issues the specified user created and issues that the user was the last one to comment on (this is a Topdesk bug/feature)
* Reorganize the application
* Write some tests
* Better configurability
