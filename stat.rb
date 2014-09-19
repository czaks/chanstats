require "bundler"
Bundler.require
require "open-uri"

class Array; def to_proc; proc { |a| a[*self] } end end
  
def open_uri uri, &block
  open uri, {ssl_verify_mode: OpenSSL::SSL::VERIFY_NONE, "Cookie" => "accept=1"}, &block
end

def stat_of uri
  # 4chan api
  open_uri uri+"/0.json" do |i|
    a = JSON.parse i.read
    
    posts = a["threads"]
      .select { |i| i["posts"][0]["sticky"] == 0 }[0..10]
      .map(&["posts"])
      .flatten
      
    return 0.0 if posts.empty?
        
    oldest = posts.min { |a,b| a["no"] <=> b["no"] }
    newest = posts.max { |a,b| a["no"] <=> b["no"] }
    
    posts = newest["no"] - oldest["no"] + 1
    time = Time.now - Time.at(oldest["time"])
    
    posts.to_f / time.to_f
  end
rescue SocketError
  retry
rescue OpenURI::HTTPError
  begin
    # mitsuba? kusaba?
    doc = Nokogiri::HTML open_uri uri+"/"
    
    mitsuba = !doc.css('.absBotDisclaimer').empty?
    kusaba = !doc.css('.footer a[href$="cultnet.net/"],
                      .footer a[href$="kusabax.org/"]').empty?
    tinyboard = !doc.css('footer a[href$="tinyboard.org/"]').empty?
    northboard = !doc.css('#software a[href$="NorthBoard/"]').empty?
    
    if not mitsuba and not tinyboard and not kusaba and not northboard
      raise "Not supported: #{uri}"
    end
    
    thread_selector = (mitsuba|northboard) ? ".thread" :
                      (kusaba|tinyboard) ? 'div[id^="thread"]' :
                        false
                        
    sticky_selector = mitsuba ? "img.stickyIcon" :
                      kusaba ? 'img[src="pin.png"]' :
                      tinyboard ? "i.fa-thumb-tack" :
                      northboard ? 'img[src$="attach.png"]' :
                        false
                        
    postinfo_selector = mitsuba ? ".postInfo" :
                        kusaba ? ".reply" :
                        tinyboard ? ".intro" :
                        northboard ? ".postinfo" :
                          false
                          
    postid_selector = mitsuba ? '.quotePost, a[title="Reply to this post"]' :
                      kusaba ? ".reflink>a:last" :
                      tinyboard ? ">.post_no" :
                      northboard ? ".post_number > a[onclick]" :
                        false
                        
    date_selector = mitsuba ? ".dateTime" :
                    kusaba ? "label:first" :
                    tinyboard ? "time" :
                    northboard ? ".post_time" :
                      false
                      
    threads = doc.css(thread_selector)
    threads = threads.select { |t| t.css(sticky_selector).empty? }[0..10]
    
    posts = threads.map { |t| t.css(postinfo_selector) }
    posts += threads if kusaba
    posts = posts.flatten
    
    posts = posts.map do |p|
      pid = p.css(postid_selector)
      
      if tinyboard
        pid = pid.last
      else
        pid = pid.first
      end
      
      pid = pid.text.strip.to_i
      
      date = p.css(date_selector).first
      if date["datetime"]
        date = date["datetime"]
      elsif date["data-utc"]
        date = Time.at(date["data-utc"].to_i)
      else
        date = date.children.last.text.strip
      end
          
      date = Time.parse(date) if date.class != Time
      
      [pid, date]
    end
    
    return 0.0 if posts.empty?
        
    oldest = posts.min { |a,b| a[0] <=> b[0] }
    newest = posts.max { |a,b| a[1] <=> b[1] }
    
    posts = newest[0] - oldest[0] + 1
    time = Time.now - oldest[1]
    
    posts.to_f / time.to_f
  rescue SocketError
    retry
  rescue Exception => e
    $error = e
    puts "Error: #{e}: #{uri}"
    0.0
  end
end

chans = nil
case ARGV[0]
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
  misc = %w[http://heretyk.tk/* http://heretichan.tk/b]
            
  vi = vi.map { |i| "https://pl.vichan.net/"+i }
  kara = kara.map { |i| "http://karachan.org/"+i }
  kiwi = kiwi.map { |i| "https://kiwiszon.org/boards/"+i }
  wilchan = wilchan.map { |i| "http://wilchan.tk/"+i }
  _8chan = _8chan.map { |i| "https://8chan.co/"+i }

  chans = misc + vi + kara + kiwi + wilchan + _8chan
when "v"
  _4chan = %w[b vg v int pol a co tg sp fit]
  _8chan = %w[b v int burgers pol anime co tg sp]

  _4chan = _4chan.map { |i| "https://boards.4chan.org/"+i }
  _8chan = _8chan.map { |i| "https://8chan.co/"+i }

  chans = _4chan + _8chan
end


require "thread"
require "pp"
results = []
ths = []
mut = Mutex.new

chans.each do |i|
  ths << Thread.new do
    k = stat_of i
    mut.synchronize do
      puts "Got #{i}"
      results << [i, k]
    end
  end
end

ths.each do |i|
  i.join
end

File.open("out.html", "w") do |f|
  f << "<!DOCTYPE html><html><body><table><tr><th>Board<th>Posts per hour</tr>"
  results.sort { |a,b| a[1] <=> b[1] }.reverse.each do |b,c|
    f << "<tr><td><a href='#{b}'>#{b}</a><td>#{c*3600}</tr>"
  end
  f << "</table></body></html>"
end

binding.pry if $error