require 'json'
require 'tmpdir'
require 'net/http'
require 'open-uri'
require "cachalot_client/version"

module CachalotClient
  SLEEP_TIME = 2
  
  class Error < StandardError; end
  
  class Client
    attr_reader :stdout 
    
    def initialize(url, service, command, work_dir, uptime=600)
      @url = url
      @service = service
      @command = command
      @work_dir = work_dir
      @uptime = uptime
      @download_path = ""
    end

    def result
      result = nil
      id = request_exec
      
      return nil if id == nil 
      result_data = get_result(id)
      
      result = CachalotClient::Result.new(result_data) if result_data != nil
      
      result
    end
    
    private

    def request_exec
      url = URI.parse(@url + "/codes")

      data = [
        ["code", data_tar(@work_dir), {filename: "data.tar"}],
        ["recipe", recipe, {filename: "recipe.json"}]
      ]
      
      req = Net::HTTP::Post.new(url.path)
      req.set_form(data, "multipart/form-data")
      
      result = Net::HTTP.new(url.host, url.port).start do |http|
        http.request(req)
      end
      
      begin
        id = JSON.parse(result.body)["id"]
      rescue
        return nil
      end

      id
    end

    def get_result(id)
      start_time = Time.now
      result = nil

      while true
        sleep SLEEP_TIME
        end_time = Time.now
        break if end_time - start_time > @uptime

        url = URI.parse(@url + "/codes/#{id}")
        req = Net::HTTP::Get.new(url.path)
        res = Net::HTTP.get(url)

        p res
        
        begin 
          result = JSON.parse(res)
        rescue
          next
        end
        
        break if result["status"].include?("executed")
        break if result["status"].include?("infeasible")
        break if result["status"].include?("execute_failed")
      end

      result 
    end
    
    def data_tar(work_dir)
      tmp_dir = Dir.mktmpdir
      FileUtils.cp_r(Dir.glob(work_dir + "/*"), tmp_dir)

      return nil if make_tarball(tmp_dir) == false 

      File.open(tmp_dir + "/data.tar", "rb")
    end

    def make_tarball(dir)
      return false if system("cd #{dir} && tar cvf data.tar .") == false
      true
    end
    
    def recipe
      recipe_json = JSON.dump(
        {
          command: @command,
          service_name: @service
        }
      )

      recipe_json
    end
  end

  class Result
    def initialize(data)
      @result_data = data
    end

    def stdout
      @result_data["result"]
    end
    
    def data_download(filedir)
      path = @result_data["result_files_path"]

      filename = "result.tar"
      filepath = "#{filedir}/#{filename}"

      open(path) do |file|
        File.write(filepath, file.read)
      end

      system("cd #{filedir} && tar xvf #{filename}")
    end
  end
end
