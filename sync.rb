require 'active_support/all'

require 'google/apis/calendar_v3'
require 'googleauth'
require 'googleauth/stores/file_token_store'

require 'fileutils'

OOB_URI = 'urn:ietf:wg:oauth:2.0:oob'
APPLICATION_NAME = 'Google Calendar API Ruby Quickstart'
CLIENT_SECRETS_PATH = 'client_secret.json'
CREDENTIALS_PATH = File.join(Dir.home, '.credentials',
                             "calendar-ruby-quickstart.yaml")
SCOPE = Google::Apis::CalendarV3::AUTH_CALENDAR_READONLY

def authorize
  FileUtils.mkdir_p(File.dirname(CREDENTIALS_PATH))

  client_id = Google::Auth::ClientId.from_file(CLIENT_SECRETS_PATH)
  token_store = Google::Auth::Stores::FileTokenStore.new(file: CREDENTIALS_PATH)
  authorizer = Google::Auth::UserAuthorizer.new(
    client_id, SCOPE, token_store
  )
  user_id = 'default'
  credentials = authorizer.get_credentials(user_id)
  if credentials.nil?
    url = authorizer.get_authorization_url(
      base_url: OOB_URI
    )
    puts "Open the following URL in the browser and enter the " +
         "resulting code after authorization"
    puts url
    code = gets
    credentials = authorizer.get_and_store_credentials_from_code(
      user_id: user_id, code: code, base_url: OOB_URI
    )
  end
  credentials
end

service = Google::Apis::CalendarV3::CalendarService.new
service.client_options.application_name = APPLICATION_NAME
service.authorization = authorize

response = service.list_events(
  'primary',
  max_results: 2500,
  single_events: true,
  order_by: 'startTime',
  time_max: 7.days.since.iso8601,
  time_min: Time.now.iso8601,
)

events = []
response.items.each do |event|
  events << OpenStruct.new(
    attendees: (event.attendees || []).map(&:email),
    start: ((event.start.date && Date.parse(event.start.date)) || event.start.date_time),
    start_str: (event.start.date || event.start.date_time.strftime('%-d %b %-I:%M %p')),
    id: event.id,
    title: event.summary,
    description: event.description,
    location: event.location,
    all_day?: event.start.date.present?,
    link: event.html_link,
  )
end

require 'todoist'

require 'denv'
Denv.load(File.join(__dir__, '.env'))

if ENV['TODOIST_API_KEY'].nil?
  raise 'required TODOIST_API_KEY'
end

module Todoist
  CLIENT = Todoist::Client.new(ENV['TODOIST_API_KEY'])

  module Resource
    def logger
      @logger ||= Logger.new(STDOUT)
    end

    def client
      Todoist::CLIENT
    end
  end
end

TARGET_PROJECT = '予定'

project = Todoist::CLIENT.projects.all.find { |p| p.name == TARGET_PROJECT }
project_items = project.items.all.select { |item| project.id == item.project_id }
events.reject(&:all_day?).each do |event|
  name = "#{event.title}"
  if project_items.find { |item| item.content == name && item.date_string == event.start_str }
    next
  end
  Todoist::CLIENT.items.create(project_id: project.id, content: name, date_string: event.start_str)
end
Todoist::CLIENT.process!

project_items = project.items.all.select { |item| project.id == item.project_id }
project_notes = Todoist::CLIENT.notes.all.select { |note| project_items.map(&:id).include?(note.item_id) }
events.reject(&:all_day?).each do |event|
  name = "#{event.title}"
  item = project_items.find { |item| item.content == name && item.date_string == event.start_str }
  if item.nil?
    next
  end

  note = project_notes.find { |note| note.item_id == item.id }
  if note.present?
    next
  end

  Todoist::CLIENT.notes.create(item_id: item.id, content: <<-CONTENT)
#{event.link}

# 参加者
#{event.attendees.count == 0 ? 'なし' : event.attendees.map{ |a| "- #{a}" }.join("\n")}

# 場所
#{event.location || 'なし'}

# 詳細
#{event.description || 'なし'}
CONTENT
end
Todoist::CLIENT.process!
