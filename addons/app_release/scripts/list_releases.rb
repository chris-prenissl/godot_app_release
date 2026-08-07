#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"

source, out_path = ARGV
unless source && out_path
  abort "usage: list_releases.rb <testflight|app_store|firebase|play> <out.json>"
end

PROJECT_ROOT = Dir.pwd
WORK_DIR = File.join(PROJECT_ROOT, ".release_tools")

begin
  ENV["BUNDLE_GEMFILE"] ||= File.join(PROJECT_ROOT, "Gemfile")
  require "bundler/setup"
  require "dotenv"
  Dotenv.load(File.join(PROJECT_ROOT, "fastlane", ".env"))
rescue Exception => e # rubocop:disable Lint/RescueException
  File.write(out_path, JSON.generate({ "error" => "setup failed: #{e.class}: #{e.message}" }))
  exit 1
end

def run_config
  @run_config ||= begin
    path = File.join(WORK_DIR, "config.json")
    File.exist?(path) ? JSON.parse(File.read(path)) : {}
  rescue JSON::ParserError
    {}
  end
end

def store_config(source)
  (run_config["stores"] || {})[source] || {}
end

def bundle_id(source)
  value = store_config(source)["bundle_identifier"].to_s.strip
  if value.empty?
    raise "no bundle identifier configured for \"#{source}\" — " \
          "set it on the matching target in release_config.tres"
  end
  value
end

def need_env(name)
  value = ENV[name].to_s.strip
  raise "#{name} is not set — fill it in fastlane/.env" if value.empty?

  value
end

def need_file(name)
  path = File.expand_path(need_env(name))
  raise "#{name} points to a missing file: #{path}" unless File.exist?(path)

  path
end

def connect_api_token
  Spaceship::ConnectAPI::Token.create(
    key_id: need_env("ASC_KEY_ID"),
    issuer_id: need_env("ASC_ISSUER_ID"),
    filepath: need_file("ASC_KEY_PATH")
  )
end

def connect_api_app(source)
  require "spaceship"

  Spaceship::ConnectAPI.token = connect_api_token
  identifier = bundle_id(source)
  app = Spaceship::ConnectAPI::App.find(identifier)
  raise "app #{identifier} not found in App Store Connect" unless app

  app
end

def testflight_releases
  app = connect_api_app("testflight")
  builds = app.get_builds(includes: "preReleaseVersion", sort: "-uploadedDate", limit: 50)
  builds.map do |b|
    {
      "date" => b.uploaded_date.to_s,
      "version" => b.pre_release_version&.version.to_s,
      "build" => b.version.to_s,
      "track" => "testflight",
      "info" => "TestFlight",
      "status" => b.processing_state.to_s.downcase
    }
  end
end

def app_store_releases
  app = connect_api_app("app_store")
  versions = app.get_app_store_versions(
    includes: "build",
    filter: { platform: "IOS" }
  )
  versions.first(50).map do |v|
    {
      "date" => v.created_date.to_s,
      "version" => v.version_string.to_s,
      "build" => v.build&.version.to_s,
      "track" => "app_store",
      "info" => "App Store",
      "status" => v.app_store_state.to_s.downcase
    }
  end
end

FIREBASE_CLI_CLIENT_ID = ENV.fetch(
  "FIREBASE_CLI_CLIENT_ID",
  "563584335869-fgrhgmd47bqnekij5i8b5pr03ho849e6.apps.googleusercontent.com"
)
FIREBASE_CLI_CLIENT_SECRET = ENV.fetch("FIREBASE_CLI_CLIENT_SECRET", "j9iVZfS8kkCEFUPaAeJV0sAi")

def firebase_access_token
  require "net/http"

  unless ENV["FIREBASE_SERVICE_CREDENTIALS"].to_s.strip.empty?
    require "googleauth"
    creds = Google::Auth::ServiceAccountCredentials.make_creds(
      json_key_io: File.open(need_file("FIREBASE_SERVICE_CREDENTIALS")),
      scope: "https://www.googleapis.com/auth/cloud-platform"
    )
    return creds.fetch_access_token!["access_token"]
  end

  config_path = File.expand_path("~/.config/configstore/firebase-tools.json")
  unless File.exist?(config_path)
    raise "no Firebase credentials — set FIREBASE_SERVICE_CREDENTIALS in fastlane/.env " \
          "(preferred), or run `firebase login`"
  end
  refresh_token = JSON.parse(File.read(config_path)).dig("tokens", "refresh_token")
  raise "the firebase CLI session has no refresh token — run `firebase login` again" unless refresh_token

  res = Net::HTTP.post_form(URI("https://oauth2.googleapis.com/token"), {
                              "client_id" => FIREBASE_CLI_CLIENT_ID,
                              "client_secret" => FIREBASE_CLI_CLIENT_SECRET,
                              "refresh_token" => refresh_token,
                              "grant_type" => "refresh_token"
                            })
  raise "firebase token refresh failed: #{res.code} #{res.body[0, 200]}" unless res.code == "200"

  JSON.parse(res.body)["access_token"]
end

def firebase_releases
  require "net/http"
  token = firebase_access_token
  app_id = need_env("FIREBASE_APP_ID_ANDROID")
  project_number = app_id.split(":")[1]
  uri = URI(
    "https://firebaseappdistribution.googleapis.com/v1/projects/#{project_number}" \
    "/apps/#{app_id}/releases?pageSize=50"
  )
  req = Net::HTTP::Get.new(uri)
  req["Authorization"] = "Bearer #{token}"
  res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) { |h| h.request(req) }
  if res.code == "403"
    raise "Firebase denied access to app #{app_id}. " \
          "Set FIREBASE_SERVICE_CREDENTIALS in fastlane/.env to a service account with the " \
          "\"Firebase App Distribution Admin\" role, and check that FIREBASE_APP_ID_ANDROID " \
          "belongs to a project you can access. " \
          "(A `firebase login` session only works if that account has access and the " \
          "App Distribution API is enabled for the project.)"
  end
  raise "Firebase API #{res.code}: #{res.body[0, 300]}" unless res.code == "200"

  (JSON.parse(res.body)["releases"] || []).map do |r|
    {
      "date" => r["createTime"].to_s,
      "version" => r["displayVersion"].to_s,
      "build" => r["buildVersion"].to_s,
      "track" => "firebase",
      "info" => "Firebase App Distribution",
      "status" => "distributed"
    }
  end
end

def play_releases
  require "google/apis/androidpublisher_v3"
  require "googleauth"
  package = bundle_id("play")
  publisher = Google::Apis::AndroidpublisherV3::AndroidPublisherService.new
  publisher.authorization = Google::Auth::ServiceAccountCredentials.make_creds(
    json_key_io: File.open(need_file("PLAY_JSON_KEY_PATH")),
    scope: "https://www.googleapis.com/auth/androidpublisher"
  )
  edit = publisher.insert_edit(package)
  tracks = publisher.list_edit_tracks(package, edit.id).tracks || []
  begin
    publisher.delete_edit(package, edit.id)
  rescue StandardError
  end

  rows = []
  tracks.each do |t|
    (t.releases || []).each do |r|
      (r.version_codes || ["?"]).each do |vc|
        rows << {
          "date" => "",
          "version" => r.name.to_s,
          "build" => vc.to_s,
          "track" => t.track.to_s,
          "info" => "Play #{t.track}",
          "status" => r.status.to_s
        }
      end
    end
  end
  rows
end

result =
  begin
    releases =
      case source
      when "testflight" then testflight_releases
      when "app_store" then app_store_releases
      when "firebase" then firebase_releases
      when "play" then play_releases
      else raise "unknown store: #{source}"
      end
    { "releases" => releases }
  rescue Exception => e # rubocop:disable Lint/RescueException
    { "error" => "#{e.class}: #{e.message}", "backtrace" => (e.backtrace || [])[0, 3] }
  end

File.write(out_path, JSON.pretty_generate(result))
