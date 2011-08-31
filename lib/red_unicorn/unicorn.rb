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
  class Timeout < ActionFailed
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
        :kill_rogues => false,
        :env => 'production'
      }.merge(opts)
      check_exec_path
      kill_rogues_before_commands(@opts[:kill_rogues])
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
      if(is_running?)
        original_pid = pid
        Process.kill('USR2', pid)
        waited = 0
        until((pid && pid != original_pid) || waited > @opts[:restart_grace])
          waited += nap(0.1)
        end
        if(waited > @opts[:restart_grace])
          raise Timeout.new("Reached max restart grace time. No new unicorn process found after #{@opts[:restart_grace]} seconds.") 
        end
        waited = 0
        until((File.exists?(@opts[:pid]) && is_running? && !child_pids(pid).empty?) || waited > @opts[:action_timeout])
          waited += nap(0.2)
        end
        if(pid == original_pid || waited > @opts[:action_timeout])
          raise UnicornError.new 'Failed to start new process'
        end
        Process.kill('QUIT', original_pid)
        while(is_running?(original_pid) && waited < @opts[:action_timeout])
          waited += nap(0.2)
        end
        errors = ['Failed to stop original unicorn process.'] if is_running?(original_pid)
        errors.push('Failed to start new unicorn process.') unless is_running?
        if(waited > @opts[:action_timeout])
          raise Timeout.new("Reached max action timeout after #{@opts[:action_timeout]} seconds. #{errors.join(' ')}")
        elsif(is_running?(original_pid))
          raise IsRunning.new(errors.join(' '))
        elsif(!is_running?)
          raise NotRunning.new(errors.join(' '))
        end
        reopen_logs
      else
        start
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
    def pid(noraise = false)
      if(File.exists?(@opts[:pid]))
        File.read(@opts[:pid]).to_s.strip.to_i
      else
        if(noraise)
          false
        else
          raise FileNotFound.new "PID file not found. Provided path: #{@opts[:pid]}"
        end
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

    # Returns unicorn master pids that are not currently tracked
    def rogue_pids
      unicorn_master_pids = %x{ps -eo pid,args | grep "unicorn.*master" | grep -v grep}.map{|line| line.split(' ').first.strip.to_i}
      unicorn_master_pids - [pid]
    end

    # Make a "best attempt" to kill off rogue processes
    def kill_rogues
      rogues = rogue_pids
      rogues.each do |rogue_master_pid|
        begin
          $stderr.puts "Found rogue unicorn master with pid: #{rogue_master_pid}. Attempting kill..."
          Process.kill('TERM', rogue_master_pid)
          sleep(0.2) if is_running?(rogue_master_pid)
          if(is_running?(rogue_master_pid))
            $stderr.puts "rogue unicorn master was signaled but appears to still be running: #{rogue_master_pid}"
          else
            $stderr.puts "rogue unicorn master was killed (PID: #{rogue_master_pid})"
          end
        rescue => e
          $stderr.puts "Failed to kill rogue unicorn master process (PID: #{rogue_master_pid}). Reason: #{e}"
        end
      end
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

    # time:: Seconds (or part of second) to sleep
    # Returns more accurate sleep duration
    def nap(time)
      start = Time.now.to_f
      sleep(time.to_f)
      Time.now.to_f - start
    end

    # Forces all commands to kill rogues before running
    def kill_rogues_before_commands(on=false)
      if(on)
        self.public_methods(false).each do |command|
          alias_method "_#{command}".to_sym, command.to_sym
          self.define_method(command) do
            kill_rogues
            self.send("_#{command}".to_sym)
          end
        end
      end
    end
  end
end


