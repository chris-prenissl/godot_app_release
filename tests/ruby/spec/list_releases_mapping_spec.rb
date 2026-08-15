require "ostruct"
require_relative "../../../addons/app_release/scripts/list_releases"

RSpec.describe "list_releases.rb mapping functions" do
  describe "#map_testflight_build" do
    it "maps a build with a pre-release version" do
      build = OpenStruct.new(
        uploaded_date: Time.utc(2026, 1, 15, 9, 30),
        pre_release_version: OpenStruct.new(version: "1.4.0"),
        version: "42",
        processing_state: "VALID"
      )

      expect(map_testflight_build(build)).to eq(
        "date" => "2026-01-15 09:30:00 UTC",
        "version" => "1.4.0",
        "build" => "42",
        "track" => "testflight",
        "info" => "TestFlight",
        "status" => "valid"
      )
    end

    it "falls back to an empty version when pre_release_version is nil" do
      build = OpenStruct.new(
        uploaded_date: Time.utc(2026, 1, 15),
        pre_release_version: nil,
        version: "42",
        processing_state: "PROCESSING"
      )

      mapped = map_testflight_build(build)
      expect(mapped["version"]).to eq("")
      expect(mapped["status"]).to eq("processing")
    end
  end

  describe "#map_app_store_version" do
    it "maps a version with a build attached" do
      version = OpenStruct.new(
        created_date: Time.utc(2026, 2, 1),
        version_string: "1.4.0",
        build: OpenStruct.new(version: "42"),
        app_store_state: "READY_FOR_SALE"
      )

      expect(map_app_store_version(version)).to eq(
        "date" => "2026-02-01 00:00:00 UTC",
        "version" => "1.4.0",
        "build" => "42",
        "track" => "app_store",
        "info" => "App Store",
        "status" => "ready_for_sale"
      )
    end

    it "falls back to an empty build when build is nil" do
      version = OpenStruct.new(
        created_date: Time.utc(2026, 2, 1),
        version_string: "1.4.0",
        build: nil,
        app_store_state: "PREPARE_FOR_SUBMISSION"
      )

      expect(map_app_store_version(version)["build"]).to eq("")
    end
  end

  describe "#map_firebase_releases" do
    it "maps each release in the response body" do
      body = JSON.generate({
                              "releases" => [
                                {
                                  "createTime" => "2026-01-15T09:30:00Z",
                                  "displayVersion" => "1.4.0",
                                  "buildVersion" => "42"
                                }
                              ]
                            })

      expect(map_firebase_releases(body)).to eq(
        [
          {
            "date" => "2026-01-15T09:30:00Z",
            "version" => "1.4.0",
            "build" => "42",
            "track" => "firebase",
            "info" => "Firebase App Distribution",
            "status" => "distributed"
          }
        ]
      )
    end

    it "returns an empty array when releases is absent" do
      expect(map_firebase_releases(JSON.generate({}))).to eq([])
    end
  end

  describe "#map_play_tracks" do
    it "emits one row per version code across tracks and releases" do
      tracks = [
        OpenStruct.new(
          track: "internal",
          releases: [
            OpenStruct.new(name: "1.4.0", status: "completed", version_codes: %w[41 42])
          ]
        ),
        OpenStruct.new(track: "production", releases: [])
      ]

      rows = map_play_tracks(tracks)

      expect(rows).to eq(
        [
          {
            "date" => "",
            "version" => "1.4.0",
            "build" => "41",
            "track" => "internal",
            "info" => "Play internal",
            "status" => "completed"
          },
          {
            "date" => "",
            "version" => "1.4.0",
            "build" => "42",
            "track" => "internal",
            "info" => "Play internal",
            "status" => "completed"
          }
        ]
      )
    end

    it "falls back to a single \"?\" row when version_codes is nil" do
      tracks = [
        OpenStruct.new(
          track: "internal",
          releases: [OpenStruct.new(name: "1.4.0", status: "completed", version_codes: nil)]
        )
      ]

      rows = map_play_tracks(tracks)
      expect(rows.size).to eq(1)
      expect(rows.first["build"]).to eq("?")
    end

    it "emits no rows when version_codes is an empty array (not nil)" do
      tracks = [
        OpenStruct.new(
          track: "internal",
          releases: [OpenStruct.new(name: "1.4.0", status: "completed", version_codes: [])]
        )
      ]

      expect(map_play_tracks(tracks)).to eq([])
    end

    it "returns an empty array when there are no tracks" do
      expect(map_play_tracks([])).to eq([])
    end
  end
end
