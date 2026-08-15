require_relative "spec_helper"

RSpec.describe "Fastfile helpers" do
  before(:each) do
    original_verbose = $VERBOSE
    $VERBOSE = nil
    load FASTFILE_PATH
    $VERBOSE = original_verbose
  end

  after(:each) do
    %w[
      IOS_SKIP_BUILD_PROCESSING_WAIT
      RELEASE_GROUPS
      RELEASE_NOTES_FILE
      ARTIFACT_PATH_ABS
      ASC_KEY_ID
      ASC_ISSUER_ID
      ASC_KEY_PATH
    ].each { |key| ENV.delete(key) }
  end

  describe "#skip_build_processing_wait?" do
    it "returns true when IOS_SKIP_BUILD_PROCESSING_WAIT is \"1\"" do
      ENV["IOS_SKIP_BUILD_PROCESSING_WAIT"] = "1"
      expect(skip_build_processing_wait?).to eq(true)
    end

    it "returns false when IOS_SKIP_BUILD_PROCESSING_WAIT is \"0\"" do
      ENV["IOS_SKIP_BUILD_PROCESSING_WAIT"] = "0"
      expect(skip_build_processing_wait?).to eq(false)
    end

    it "returns false when unset" do
      expect(skip_build_processing_wait?).to eq(false)
    end
  end

  describe "#tester_groups" do
    it "splits and strips a comma-separated RELEASE_GROUPS" do
      ENV["RELEASE_GROUPS"] = "internal-testers, beta-testers ,qa"
      expect(tester_groups).to eq(["internal-testers", "beta-testers", "qa"])
    end

    it "returns nil when RELEASE_GROUPS is blank" do
      ENV["RELEASE_GROUPS"] = ""
      expect(tester_groups).to be_nil
    end

    it "returns nil when RELEASE_GROUPS is unset" do
      expect(tester_groups).to be_nil
    end
  end

  describe "#release_notes" do
    it "reads and strips the file named by RELEASE_NOTES_FILE" do
      ENV["RELEASE_NOTES_FILE"] = File.expand_path(
        "../../fixtures/ios_basic/release_notes.txt", __dir__
      )
      expect(release_notes).to eq("Fixes a crash on launch.")
    end

    it "returns empty string when RELEASE_NOTES_FILE is unset" do
      expect(release_notes).to eq("")
    end

    it "returns empty string when RELEASE_NOTES_FILE points at a missing file" do
      ENV["RELEASE_NOTES_FILE"] = "/no/such/file.txt"
      expect(release_notes).to eq("")
    end
  end

  describe "#artifact" do
    it "returns the path when ARTIFACT_PATH_ABS points to an existing file" do
      ENV["ARTIFACT_PATH_ABS"] = __FILE__
      expect(artifact).to eq(__FILE__)
    end

    it "calls UI.user_error! when ARTIFACT_PATH_ABS is unset" do
      expect { artifact }.to raise_error(/ARTIFACT_PATH_ABS is not set/)
    end

    it "calls UI.user_error! when ARTIFACT_PATH_ABS points at a missing file" do
      ENV["ARTIFACT_PATH_ABS"] = "/no/such/artifact.ipa"
      expect { artifact }.to raise_error(/artifact not found/)
    end
  end

  describe "#connect_api_key" do
    it "forwards the three ASC_* env vars" do
      ENV["ASC_KEY_ID"] = "K1"
      ENV["ASC_ISSUER_ID"] = "I1"
      ENV["ASC_KEY_PATH"] = "/tmp/key.p8"
      expect(connect_api_key).to eq(key_id: "K1", issuer_id: "I1", key_filepath: "/tmp/key.p8")
    end

    it "raises KeyError when ASC_KEY_ID is missing" do
      ENV["ASC_ISSUER_ID"] = "I1"
      ENV["ASC_KEY_PATH"] = "/tmp/key.p8"
      expect { connect_api_key }.to raise_error(KeyError)
    end
  end
end
