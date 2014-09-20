require "bundler"
Bundler.require
require "open-uri"
require "timeout"

# Some weird polish boards have invalid ssl cert, require a cookie, etc.
def open_uri uri, &block
  open uri, {ssl_verify_mode: OpenSSL::SSL::VERIFY_NONE, "Cookie" => "accept=1"}, &block
end

def stat_of uri
  # Use 4chan api if it's possible
  open_uri uri+"/0.json" do |i|
    a = JSON.parse i.read
    
    # Select all threads
    posts = a["threads"].
      # ...that are not sticky, but at most 10 threads of a page
      select { |i| i["posts"][0]["sticky"] == 0 }[0..10].
      # ...select all posts in those threads
      map { |i| i["posts"] }.
      # ...and flatten the array
      flatten
      
    # If a board doesn't have any posts, then return 0 posts per second
    return 0.0 if posts.empty?
        
    # Select the oldest post
    oldest = posts.min { |a,b| a["no"] <=> b["no"] }
    # And the newest posts
    newest = posts.max { |a,b| a["no"] <=> b["no"] }
    
    # Calculate a difference in post numbers between them
    posts = newest["no"] - oldest["no"] + 1
    # Calculate time difference between now and an oldest post
    time = Time.now - Time.at(oldest["time"])
    
    # Calculate a post per second fraction of a given board
    posts.to_f / time.to_f
  end
rescue SocketError
  # If network fails, retry
  retry
rescue OpenURI::HTTPError, JSON::ParserError
  # 4chan api doesn't work here, let's try manually parsing HTML
  begin
    doc = Nokogiri::HTML open_uri uri+"/"
    
    # Let's detect an engine of a board
    mitsuba = !doc.css('.absBotDisclaimer').empty?
      # mitsuba is for 4chan and karachan, since they are compatible
    kusaba = !doc.css('.footer a[href$="cultnet.net/"],
                       .footer a[href$="kusabax.org/"],
                       #footer a[href$="cultnet.net/"]').empty?
    tinyboard = !doc.css('footer a[href$="tinyboard.org/"]').empty?
    northboard = !doc.css('#software a[href$="NorthBoard/"]').empty?
    krautchan = uri =~ /krautchan\.net/
    fourtwenty = uri =~ /420chan\.org/
    
    if not mitsuba and not tinyboard and not kusaba and not northboard \
      and not krautchan and not fourtwenty
      
      raise "Not supported: #{uri}"
    end
    
    # A CSS selector that would give us every thread
    thread_selector = (mitsuba|northboard|krautchan) ? ".thread" :
                      (kusaba|tinyboard) ? 'div[id^="thread"]:not(#thread_controls)' :
                      fourtwenty ? 'div[id*="thread"]' :
                        false
                        
    # A CSS selector that would determine, if a given thread is sticky or not
    sticky_selector = mitsuba ? "img.stickyIcon" :
                      kusaba ? 'img[src="pin.png"]' :
                      tinyboard ? "i.fa-thumb-tack" :
                      northboard ? 'img[src$="attach.png"]' :
                      krautchan ? 'img[src$="sticky.png"]' :
                      fourtwenty ? 'FIXME' :
                        false
    
    # This one should give us a part of a post, that would apply both to
    # a thread and posts inside.
    postinfo_selector = mitsuba ? ".postInfo" :
                        kusaba ? ".reply" :
                        tinyboard ? ".intro" :
                        northboard ? ".postinfo" :
                        krautchan ? ".postheader" :
                        fourtwenty ? ".thread_header, .replyheader" :
                          false
    
    # A selector to give us a post number
    postid_selector = mitsuba ? '.quotePost, a[title="Reply to this post"]' :
                      (kusaba|fourtwenty) ? ".reflink>a:last" :
                      tinyboard ? ">.post_no" :
                      northboard ? ".post_number > a[onclick]" :
                      krautchan ? ".postnumber > .quotelink:last" :
                        false
                        
    # A selector to give us a date of a post
    date_selector = mitsuba ? ".dateTime" :
                    kusaba ? "label:first, .post_header" :
                    tinyboard ? "time" :
                    northboard ? ".post_time" :
                    krautchan ? ".postdate" :
                    fourtwenty ? ".idhighlight" :
                      false
                     
    # Select all threads...
    threads = doc.css(thread_selector)
    # ...that are not sticky and at most 10 of them
    threads = threads.select { |t| t.css(sticky_selector).empty? }[0..10]

    # Select both threads and posts
    posts = threads.map { |t| t.css(postinfo_selector) }
    # Unfortunately, we aren't able to do it via CSS selectors on kusaba,
    # so let's manually add the threads to the posts array
    posts += threads if kusaba
    # Flatten the array, so that [[1,2,3],[4,5,6]] becomes [1,2,3,4,5,6]
    posts = posts.flatten
    
    # Parse the posts
    posts = posts.map do |p|
      # Select a postid
      pid = p.css(postid_selector)
      
      # A minor difference in tinyboard handling
      if tinyboard
        pid = pid.last
      else
        pid = pid.first
      end
      
      # Get a post id
      pid = pid.text.sub("No.", "").strip.to_i
      
      # Select a date
      date = p.css(date_selector).first
      # If it can be done without parsing a date, let's do it.
      
      if date["datetime"] # Tinyboard
        date = date["datetime"]
      elsif date["data-utc"] # 4chan
        date = Time.at(date["data-utc"].to_i)
      else # It can't be selected cleanly on kusaba, so a little hackery here
        date = date.children.select do |i|
          i.class == Nokogiri::XML::Text
        end.map(&:text).join
      end
          
      # Time.parse is a pretty cool guy, it can parse every date and
      # not afraid of anything
      date = Time.parse(date) if date.class != Time
      
      # Return an array of tuples (postid, date)
      [pid, date]
    end
    
    # Return 0, if there are no posts
    return 0.0 if posts.empty?
        
    # Select the oldest post
    oldest = posts.min { |a,b| a[0] <=> b[0] }
    # Select the newest post
    newest = posts.max { |a,b| a[1] <=> b[1] }
    
    # Calculate, how many post ids have passed between the oldest post and now
    posts = newest[0] - oldest[0] + 1
    time = Time.now - oldest[1]
    
    posts.to_f / time.to_f
  rescue SocketError
    # If network fails, retry
    retry
  rescue Exception => e
    # Some error happened. Let's save it for further inspection
    $error = e
    puts "Error: #{e}: #{uri}"
    0.0
  end
end

# Select a chanset
chans = nil
case ARGV[0]
# Polish chans
when "pl"
  vi = %w[b cp r+oc id waifu wiz veto int slav
          sci psl h c c++ vg lsd ku fso btc trv
          a az ac mu tv lit vp x hk fr
          sr swag sex pro med soc trap pr psy
          meta chan mit 3 fem synch]
  kara = %w[4 b fz z r id $ c co a edu f fa
            h kib ku l med mil mu oc p po pony
            sci sp tech thc trv v8 vg wall x og
            int kara g hen s dew]
  kiwi = %w[b a co hob kul tec v wc kiwi]
  wilchan = %w[b vg admin]
  _8chan = %w[rzabczan heretyk flutter ebolachan
              sierpchan kib g]
  misc = %w[http://heretyk.tk/*]
            
  vi = vi.map { |i| "https://pl.vichan.net/"+i }
  kara = kara.map { |i| "http://karachan.org/"+i }
  kiwi = kiwi.map { |i| "https://kiwiszon.org/boards/"+i }
  wilchan = wilchan.map { |i| "http://wilchan.tk/"+i }
  _8chan = _8chan.map { |i| "https://8chan.co/"+i }

  chans = misc + vi + kara + kiwi + wilchan + _8chan
# 4chan vs 8chan revolution
when "v"
  _4chan = %w[b vg v int pol a co tg sp fit g]
  _8chan = %w[b v int pol a co tg sp tech gg]
  misc = %w[https://krautchan.net/int
            http://boards.420chan.org/b]
  
  

  _4chan = _4chan.map { |i| "https://boards.4chan.org/"+i }
  _8chan = _8chan.map { |i| "https://8chan.co/"+i }

  chans = _4chan + _8chan + misc
end


require "thread"
require "pp"
results = []
ths = []
# This mutex synchronizes screen output and array writes
mut = Mutex.new

chans.each do |i|
  # Spawn a thread for each board...
  ths << Thread.new do
    # Give 5 minutes for the fetching and calculations to happen.
    begin
      Timeout::timeout 300 do
        # calculate stats for it and
        k = stat_of i
        mut.synchronize do
          # Feedback that a given board has been handled
          puts "Got #{i}"
          # Push stats of a given board to our array
          results << [i, k]
        end
      end
    rescue Timeout::Error
      mut.synchronize do
        puts "Timeout: #{i}"
      end
      retry
    end
  end
end

# Wait until all threads are done waiting
ths.each do |i|
  i.join
end

case ARGV[1]
when "json" # JSON output
  File.open("history/#{Time.now.to_i}.json", "w") do |f|
    f << results.to_json
  end
else # HTML output
  # Output the results, sorted by the activity, in a posts per hour format
  File.open("out.html", "w") do |f|
    f << "<!DOCTYPE html><html><body><table><tr><th>Board<th>Posts per hour</tr>"
    results.sort { |a,b| a[1] <=> b[1] }.reverse.each do |b,c|
      f << "<tr><td><a href='#{b}'>#{b}</a><td>#{c*3600}</tr>"
    end
    f << "</table></body></html>"
  end
end

# Run an interactive console if there were any errors
binding.pry if $error
