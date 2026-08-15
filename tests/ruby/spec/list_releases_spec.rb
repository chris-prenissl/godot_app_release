require "open3"
require "fileutils"
require "json"
require "tmpdir"

RSpec.describe "list_releases.rb" do
  let(:script_path) do
    File.expand_path("../../../addons/app_release/scripts/list_releases.rb", __dir__)
  end
  let(:ruby_project_fixture) do
    File.expand_path("../../fixtures/ruby_project", __dir__)
  end

  around(:each) do |example|
    Dir.mktmpdir do |dir|
      FileUtils.cp_r("#{ruby_project_fixture}/.", dir)
      @project_root = dir
      example.run
    end
  end

  def out_path
    @out_path ||= File.join(@project_root, "out.json")
  end

  def run_script(*args, env: {})
    base_env = {
      "BUNDLE_GEMFILE" => File.join(@project_root, "Gemfile"),
      "FIREBASE_SERVICE_CREDENTIALS" => nil,
      "ASC_KEY_ID" => nil,
      "ASC_ISSUER_ID" => nil,
      "ASC_KEY_PATH" => nil,
      "FIREBASE_APP_ID_ANDROID" => nil,
      "PLAY_JSON_KEY_PATH" => nil
    }
    stdout, stderr, status = Bundler.with_unbundled_env do
      Open3.capture3(base_env.merge(env), "ruby", script_path, *args, chdir: @project_root)
    end
    { stdout: stdout, stderr: stderr, status: status, out_path: out_path }
  end

  def run_for_source(source, env: {})
    result = run_script(source, out_path, env: env)
    JSON.parse(File.read(result[:out_path]))
  end

  def write_config(stores)
    dir = File.join(@project_root, ".release_tools")
    FileUtils.mkdir_p(dir)
    File.write(File.join(dir, "config.json"), JSON.generate({ "stores" => stores }))
  end

  describe "argument validation" do
    it "aborts with a usage message when called with no arguments" do
      result = run_script
      expect(result[:status].success?).to be(false)
      expect(result[:stderr]).to include("usage: list_releases.rb")
      expect(File.exist?(result[:out_path])).to be(false)
    end

    it "aborts with a usage message when called with only one argument" do
      result = run_script("testflight")
      expect(result[:status].success?).to be(false)
      expect(result[:stderr]).to include("usage: list_releases.rb")
    end
  end

  describe "setup failures" do
    it "always writes valid JSON to out_path even on total failure" do
      FileUtils.rm_f(File.join(@project_root, "Gemfile"))
      FileUtils.rm_f(File.join(@project_root, "Gemfile.lock"))

      result = run_for_source("testflight")

      expect(result).to have_key("error")
      expect(result["error"]).to include("setup failed")
    end
  end

  describe "bundle_id / run_config" do
    {
      "config.json is absent entirely" => -> {},
      "config.json is malformed JSON" => lambda {
        dir = File.join(@project_root, ".release_tools")
        FileUtils.mkdir_p(dir)
        File.write(File.join(dir, "config.json"), "{not valid json")
      },
      "stores is empty" => -> { write_config({}) },
      "the source has no entry under stores" => lambda {
        write_config({ "testflight" => { "bundle_identifier" => "com.example.app" } })
      }
    }.each do |description, setup|
      it "errors with no bundle identifier configured when #{description}" do
        instance_exec(&setup)

        result = run_for_source("play")

        expect(result["error"]).to include("no bundle identifier configured for \"play\"")
      end
    end
  end

  describe "need_file" do
    it "errors when FIREBASE_SERVICE_CREDENTIALS points at a missing file" do
      write_config({})

      result = run_for_source(
        "firebase", env: { "FIREBASE_SERVICE_CREDENTIALS" => "/no/such/service-account.json" }
      )

      expect(result["error"]).to include("FIREBASE_SERVICE_CREDENTIALS points to a missing file")
    end
  end

  describe "credential errors" do
    it "errors when Firebase credentials are missing entirely" do
      write_config({})

      result = run_for_source("firebase", env: { "HOME" => @project_root })

      expect(result["error"]).to match(/no Firebase credentials/)
    end
  end

  describe "unknown source" do
    it "errors on a source that is not testflight/app_store/firebase/play" do
      write_config({})

      result = run_for_source("unknown_store")

      expect(result["error"]).to include("unknown store: unknown_store")
    end
  end
end
