#TODO: Add method of checking for rouge unicorn process and killing them
module RedUnicorn

  # Descriptive error classes
  class UnicornError < StandardError
  end
  class ActionFailed < UnicornError
  end
  class FileNotFound < UnicornError
  end
  class NotRunning < UnicornError
  end
  class IsRunning < UnicornError
  end

  class Unicorn
    # pid:: Path to unicorn PID file
    # return_codes:: Hash of return codes (defined in executable bin file)
    # exec_path:: Path to unicorn executable
    # Create a new instance of unicorn interactor
    def initialize(opts={})
      @opts = {
        :pid => '/var/run/unicorn/unicorn.pid',
        :exec_path => '/var/www/shared/bundle/bin/unicorn_rails',
        :config_path => '/etc/unicorn/app.rb',
        :action_timeout => 30,
        :restart_grace => 8,
        :env => 'production'
      }.merge(opts)
      check_exec_path
    end

    # Start a new unicorn process
    def start
      process_is :stopped do
        %x{#{@opts[:exec_path]} --daemonize --env #{@opts[:env]} --config-file #{@opts[:config_path]}}
      end
    end

    # Stop current unicorn process
    def stop
      process_is :running do
        Process.kill('QUIT', pid)
      end
    end

    # Halts the current unicorn process
    def halt
      process_is :running do
        Process.kill('TERM', pid)
      end
    end

    # Graceful restart
    def restart
      process_is :running do
        original_pid = pid
        Process.kill('USR2', pid)
        sleep(@opts[:restart_grace]) # give unicorn some breathing room
        waited = 0
        until((File.exists?(@opts[:pid]) && is_running? && !child_pids(pid).empty?) || waited > @opts[:action_timeout])
          sleep_start = Time.now.to_f
          sleep(0.2)
          waited += Time.now.to_f - sleep_start
        end
        if(pid == original_pid || waited > @opts[:action_timeout])
          raise UnicornError.new 'Failed to start new process'
        end
        Process.kill('QUIT', original_pid)
        while(is_running?(original_pid) && waited < @opts[:action_timeout])
          sleep_start = Time.now.to_f
          sleep(0.2)
          waited += Time.now.to_f - sleep_start
        end
        raise IsRunning.new 'Failed to stop original unicorn process' if is_running?(original_pid)
        raise NotRunning.new 'Failed to start new unicorn process'  unless is_running?
        reopen_logs
      end
    end

    # Reload unicorn configuration
    def reload
      process_is :running do
        Process.kill('HUP', pid)
      end
    end

    # Add new worker process
    def add_child
      process_is :running do
        Process.kill('TTIN', pid)
      end
    end

    # Remove worker process
    def remove_child
      process_is :running do
        Process.kill('TTOU', pid)
      end
    end

    # Stops all worker processes but
    # keeps the master process alive
    def remove_all_children
      process_is :running do
        Process.kill('WINCH', pid)
      end
    end

    # Reopen log files
    def reopen_logs
      process_is :running do
        Process.kill('USR1', pid)
      end
    end

    # Return status of current process
    def status
      process_is :running do
        puts '* unicorn is running'
      end
    end

    private

    # Return process ID from PID file
    def pid
      if(File.exists?(@opts[:pid]))
        File.read(@opts[:pid]).to_s.strip.to_i
      else
        raise FileNotFound.new "PID file not found. Provided path: #{@opts[:pid]}"
      end
    end

    # Check if unicorn is currently running
    def is_running?(custom_pid = nil)
      begin
        Process.kill(0, custom_pid || pid)
        true
      rescue
        false
      end
    end

    # state:: :running or :stopped
    # Ensure process is in given state and run some code if
    # the caller felt like passing some along
    def process_is(state)
      case state
        when :running
          raise NotRunning.new 'Unicorn is not currently running' unless is_running?
        when :stopped
          raise IsRunning.new 'Unicorn is currently running' if is_running?
        else
          raise UnicornError.new 'Unknown process state received'
      end
      yield if block_given?
    end

    # parent_pid:: Parent process ID
    # Returns array of child process IDs for the given parent
    def child_pids(parent_pid)
      process_list = %x{ps -eo pid,ppid | grep #{parent_pid}}
      process_list.map(&:strip).find_all{|pr| pr.split.last == parent_pid.to_s }.map{|pr| pr.split.first.strip.to_i }
    end

    # Check validity of unicorn exec path
    def check_exec_path
      unless(File.exists?(@opts[:exec_path]))
        test_path = '/var/www/shared/bundle/bin/unicorn_rails'
        if(File.exists?(test_path))
          @opts[:exec_path] = test_path
        else
          raise FileNotFound.new "Failed to find executable unicorn. Set path is: #{@opts[:exec_path]}"
        end
      end
    end
  end
end


