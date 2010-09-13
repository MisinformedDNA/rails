require 'isolation/abstract_unit'

module ApplicationTests
  class RoutingTest < Test::Unit::TestCase
    include ActiveSupport::Testing::Isolation

    def setup
      build_app
      boot_rails
      require 'rack/test'
      extend Rack::Test::Methods
    end

    def app(env = "production")
      old_env = ENV["RAILS_ENV"]

      @app ||= begin
        ENV["RAILS_ENV"] = env
        require "#{app_path}/config/environment"
        Rails.application
      end
    ensure
      ENV["RAILS_ENV"] = old_env
    end

    def simple_controller
      controller :foo, <<-RUBY
        class ExpiresController < ApplicationController
          def expires_header
            expires_in 10, :public => !params[:private]
            render :text => ActiveSupport::SecureRandom.hex(16)
          end

          def expires_etag
            render_conditionally(:etag => "1")
          end

          def expires_last_modified
            $last_modified ||= Time.now.utc
            render_conditionally(:last_modified => $last_modified)
          end
        private
          def render_conditionally(headers)
            if stale?(headers.merge(:public => !params[:private]))
              render :text => ActiveSupport::SecureRandom.hex(16)
            end
          end
        end
      RUBY

      app_file 'config/routes.rb', <<-RUBY
        AppTemplate::Application.routes.draw do
          match ':controller(/:action)'
        end
      RUBY
    end

    def test_cache_works_with_expires
      simple_controller

      get "/expires/expires_header"
      assert_equal "miss, store",        last_response.headers["X-Rack-Cache"]
      assert_equal "max-age=10, public", last_response.headers["Cache-Control"]

      body = last_response.body

      get "/expires/expires_header"

      assert_equal "fresh", last_response.headers["X-Rack-Cache"]

      assert_equal body, last_response.body
    end

    def test_cache_works_with_expires_private
      simple_controller

      get "/expires/expires_header", :private => true
      assert_equal "miss",                last_response.headers["X-Rack-Cache"]
      assert_equal "private, max-age=10", last_response.headers["Cache-Control"]

      body = last_response.body

      get "/expires/expires_header", :private => true
      assert_equal "miss",           last_response.headers["X-Rack-Cache"]
      assert_not_equal body,         last_response.body
    end

    def test_cache_works_with_etags
      simple_controller

      get "/expires/expires_etag"
      assert_equal "miss, store", last_response.headers["X-Rack-Cache"]
      assert_equal "public",      last_response.headers["Cache-Control"]

      body = last_response.body
      etag = last_response.headers["ETag"]

      get "/expires/expires_etag", {}, "If-None-Match" => etag
      assert_equal "stale, valid, store", last_response.headers["X-Rack-Cache"]
      assert_equal body,                  last_response.body
    end

    def test_cache_works_with_etags_private
      simple_controller

      get "/expires/expires_etag", :private => true
      assert_equal "miss",                                last_response.headers["X-Rack-Cache"]
      assert_equal "must-revalidate, private, max-age=0", last_response.headers["Cache-Control"]

      body = last_response.body
      etag = last_response.headers["ETag"]

      get "/expires/expires_etag", {:private => true}, "If-None-Match" => etag
      assert_equal     "miss", last_response.headers["X-Rack-Cache"]
      assert_not_equal body,   last_response.body
    end

    def test_cache_works_with_last_modified
      simple_controller

      get "/expires/expires_last_modified"
      assert_equal "miss, store", last_response.headers["X-Rack-Cache"]
      assert_equal "public",      last_response.headers["Cache-Control"]

      body = last_response.body
      last = last_response.headers["Last-Modified"]

      get "/expires/expires_last_modified", {}, "If-Modified-Since" => last
      assert_equal "stale, valid, store", last_response.headers["X-Rack-Cache"]
      assert_equal body,                  last_response.body
    end

    def test_cache_works_with_last_modified_private
      simple_controller

      get "/expires/expires_last_modified", :private => true
      assert_equal "miss",                                last_response.headers["X-Rack-Cache"]
      assert_equal "must-revalidate, private, max-age=0", last_response.headers["Cache-Control"]

      body = last_response.body
      last = last_response.headers["Last-Modified"]

      get "/expires/expires_last_modified", {:private => true}, "If-Modified-Since" => last
      assert_equal     "miss", last_response.headers["X-Rack-Cache"]
      assert_not_equal body,   last_response.body
    end
  end
end
