module Rack
  class RevisionInfo
    INJECT_ACTIONS = [:after, :before, :append, :prepend, :swap, :inner_html]

    def initialize(app, opts={})
      @app = app
      path = opts[:path] or raise ArgumentError, "You must specify directory of your local repository!"
      revision, date = get_revision_info(path, opts)
      @revision_info = "#{get_revision_label(opts)} #{revision || 'unknown'}"
      @revision_info << " (#{date.strftime(get_date_format(opts))})" if date
      @action = (opts.keys & INJECT_ACTIONS).first
      if @action
        require 'hpricot'
        @selector = opts[@action]
      end
    end

    def call(env)
      status, headers, body = @app.call(env)
      if headers['Content-Type'].include?('text/html') && !Rack::Request.new(env).xhr?
        html = ""
        body.each { |s| html << s }
        body = html
        begin
          if @action
            doc = Hpricot(body)
            elements = doc.search(@selector).compact
            if elements.size > 0
              elements = elements.first if @action == :swap
              elements.send(@action, @revision_info)
              body = doc.to_s
            end
          end
        rescue => e
          puts e
          puts e.backtrace
        end
        body << %(\n<!-- #{@revision_info} -->\n)
        body = [body]
      end
      [status, headers, body]
    end

    protected

    def get_revision_label(opts={})
      revision_label = 'Revision'
      unless opts[:revision_label].nil?
        revision_label = opts[:revision_label]
      end
      revision_label
    end

    def get_date_format(opts={})
      date_format = "%Y-%m-%d %H:%M:%S %Z"
      unless opts[:date_format].nil?
        date_format = opts[:date_format]
      end
      date_format
    end

    def get_revision_info(path, opts={})
      case detect_type(path)
      when :git
        revision_regex_extra = '+'
        if not opts[:short_git_revisions].nil? and opts[:short_git_revisions]
          revision_regex_extra = '{8}'
        end
        info = `cd #{path}; LC_ALL=C git log -1 --pretty=medium`
        revision = info[/commit\s([a-z0-9]#{revision_regex_extra})/, 1]
        date = (d = info[/Date:\s+(.+)$/, 1]) && (DateTime.parse(d) rescue nil)
      when :svn
        info = `cd #{path}; LC_ALL=C svn info`
        revision = info[/Revision:\s(\d+)$/, 1]
        date = (d = info[/Last Changed Date:\s([^\(]+)/, 1]) && (DateTime.parse(d.strip) rescue nil)
      else
        revision, date = nil, nil
      end
      [revision, date]
    end

    def detect_type(path)
      return :git if ::File.directory?(::File.join(path, ".git"))
      return :svn if ::File.directory?(::File.join(path, ".svn"))
      :unknown
    end

  end
end
