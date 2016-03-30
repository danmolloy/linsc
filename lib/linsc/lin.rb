require 'rubygems'
require 'mechanize'
require 'csv'
require 'fileutils'
require 'i18n'
require_relative 'proxy'
require_relative 'proxy_handler'
require_relative 'csv_handlers'

# tuck this away into a core_extensions module
class String
  def alnum
    return self.gsub(/[^\p{Alnum}\p{Space}]/u, ' ')
  end
end

class NilClass
  def text
    return nil
  end
  def [](options = {})
    return nil
  end
  def css(options = {})
    return nil
  end
  def gsub(a, b)
    return nil
  end
  def at_css(options = {})
    return nil
  end
  def slice(a, b, options = {})
    return nil
  end
  def include?(a)
    return false
  end
  def gsub!(a, b)
    return nil
  end

end

class LinScraper
  include CSVHandlers

  def initialize(working_dir, input_file, options)
    @working_dir, @input_file, @options = working_dir, input_file, options
    @output_update = "#{@working_dir}contact_update.csv" if @options[:update]
    @output_insert = "#{@working_dir}contact_insert.csv" if @options[:insert]
    @output_employment = "#{@working_dir}contact_employment.csv"
    @output_education = "#{@working_dir}contact_education.csv"
    @cooldown = 20
    @noproxy = options[:noproxy]
    @proxies = ProxyHandler.new(@cooldown) unless @options[:noproxy]
    @headers = get_headers(@input_file)
    @new_headers = ["Contact ID", "CV TR", "Account Name", "Linkedin Import Status", "First Name", "Last Name", "Email", "LinkedIn Profile", "Candidate ID",
            "LIN 1st Degree", "Title", "Contact Country", "Contact LIN Sector", "Resume Last Updated", "LIN Import Date", "CV Uploaded",
            "Employer 1 Title", "Employer Organization Name 1", "Employer 1 Start Date",
            "Employer 1 End Date", "Employer 1 Location", "Employer 1 Description",
            "Employer 2 Title", "Employer Organization Name 2", "Employer 2 Start Date",
            "Employer 2 End Date", "Employer 2 Location", "Employer 2 Description",
            "Employer 3 Title", "Employer Organization Name 3", "Employer 3 Start Date",
            "Employer 3 End Date", "Employer 3 Location", "Employer 3 Description",
            "License or Certification Name 1", "License or Certification Name 2",
            "License or Certification Credential Type", "Education School 1",
            "Education Degree Name 1", "Education Degree Date 1",
            "Education School 2", "Education Degree Name 2",
            "Education Degree Date 2", "Text Resume"]
    @new_headers.each do |header|
      @headers << header unless @headers.include?(header)
    end
    @headers.delete('Urls')
    @employment_headers = ["Contact", "Employer Name", "Job Title", "Start Date", "End Date", "Location"]
    @education_headers = ["Contact", "School Name", "Major", "Graduation Year"]
    @input_length = %x(wc -l "#{@input_file}").split[0].to_i - 1
    I18n.available_locales = [:en]
    if (@output_update && File.exist?(@output_update)) || (@output_insert && File.exist?(@output_insert))
      if @output_update
        update_length = CSV.read(@output_update, headers: true).length
      else
        update_length = 0
      end
      if @output_insert
        insert_length = CSV.read(@output_insert, headers: true).length
      else
        insert_length = 0
      end
      @start = update_length + insert_length
    end
    [@output_insert, @output_update, @output_education, @output_employment].each do |file|
      if file
        create_file(file) unless File.exist?(file)
      end
    end
  end

  def name_check(lin_name, csv_name)
    csv_array = csv_name.downcase.alnum.split(" ")
    lin_array = lin_name.downcase.alnum.split(" ")
    match = true
    csv_array.each do |chunk|
      unless lin_array.include?(chunk)
        match = false
      end
    end
    return match
  end

  def scrape_contact(input_row, page, mode)
    row = CSV::Row.new(@headers, [])
    name = page.at_css("#name")&.text&.split
    contact_id = input_row["Contact ID"]
    cv_tr = input_row["CV TR"]
    acc_name = input_row["Account Name"]
    import_status = input_row["Linkedin Import Status"]
    email = input_row["Email"]
    lin_profile = input_row["Linkedin Profile"]
    cand_id = input_row["Candidate ID"]
    cand_source = input_row["LIN 1st Degree"]
    title = page.at_css(".headline.title")&.text
    country = page.at_css("#demographics .locality")&.text
    sector = page.at_css("#demographics .descriptor:not(.adr)")&.text

    positions = page.css("#experience .positions .position")
    if positions
      e1_title = positions[0]&.at_css(".item-title")&.text
      e1_org = positions[0]&.at_css(".item-subtitle")&.text
      e1_start = positions[0]&.css(".date-range time")[0]&.text
      e1_end = positions[0]&.css(".date-range time")[1]&.text
      e1_loc = positions[0]&.at_css(".location")&.text
      e1_desc = positions[0]&.at_css(".description")&.text
      e2_title = positions[1]&.at_css(".item-title")&.text
      e2_org = positions[1]&.at_css(".item-subtitle")&.text
      e2_start = positions[1]&.css(".date-range time")[0]&.text
      e2_end = positions[1]&.css(".date-range time")[1]&.text
      e2_loc = positions[1]&.at_css(".location")&.text
      e2_desc = positions[1]&.at_css(".description")&.text
      e3_title = positions[2]&.at_css(".item-title")&.text
      e3_org = positions[2]&.at_css(".item-subtitle")&.text
      e3_start = positions[2]&.css(".date-range time")[0]&.text
      e3_end = positions[2]&.css(".date-range time")[1]&.text
      e3_loc = positions[2]&.at_css(".location")&.text
      e3_desc = positions[2]&.at_css(".description")&.text
    end

    certs = page.css(".certifications .certification")
    if certs
      c1_name = certs[0]&.at_css(".item-title")&.text
      c2_name = certs[1]&.at_css(".item-title")&.text
      c_type  = certs[0]&.at_css(".item-subtitle")&.text
    end

    schools = page.css("#education .schools .school")
    if schools
      s1_name = schools[0]&.at_css(".item-title")&.text
      s2_name = schools[1]&.at_css(".item-title")&.text
      s1_start = schools[0]&.css(".date-range time")[0]&.text
      s2_start = schools[1]&.css(".date-range time")[0]&.text
      s1_end = schools[0]&.css(".date-range time")[1]&.text
      s2_end = schools[1]&.css(".date-range time")[1]&.text
      s1_degree = schools[0]&.at_css(".item-subtitle")&.text
      s2_degree = schools[1]&.at_css(".item-subtitle")&.text
    end

    summary = page.at_css("#summary .description")
    summary&.css('br').each{|br| br.replace "\n"} if summary

    text_resume = "\n\n***IMPORTED FROM LINKEDIN***\n#{lin_profile}\n\n"
    text_resume += name.join(" ")
    text_resume += "\n#{email}"
    text_resume += "\nTitle: #{title}" if title
    text_resume += "\nLocation: #{country}" if country
    text_resume += "\nSector: #{sector}" if sector
    text_resume += "\n\nSUMMARY\n#{summary.text}" if summary
    text_resume += "\n\nEXPERIENCE\n" if positions && positions.length > 0
    positions.each do |position|
      jtitle = position.at_css(".item-title")
      jcompany = position.at_css(".item-subtitle")
      jdates = position.at_css(".date-range")
      jlocation = position.at_css(".location")
      jdesc = position.at_css(".description")
      jdesc.css('br').each{|br| br.replace "\n"} if jdesc
      text_resume += "\n#{jtitle.text}\n" if jtitle
      text_resume += " - #{jcompany.text}\n" if jcompany && jcompany.text.length > 0
      text_resume += "#{jdates.text}\n" if jdates
      text_resume += "#{jlocation.text}\n" if jlocation
      text_resume += "#{jdesc.text}\n" if jdesc
    end
    text_resume += "\n\nEDUCATION\n" if schools && schools.length > 0
    schools.each do |school|
      stitle = school.at_css(".item-title")
      sdegree = school.at_css(".item-subtitle")
      sdates = school.at_css(".date-range")
      sdesc = school.at_css(".description")
      sdesc.css('br').each{|br| br.replace "\n"} if sdesc
      text_resume += "\n#{stitle.text}\n" if stitle
      text_resume += " - #{sdegree.text}\n" if sdegree && sdegree.text.length > 0
      text_resume += "#{sdates.text}\n" if sdates
      text_resume += "#{sdesc.text}\n" if sdesc
    end
    text_resume  += "\n\nCERTIFICATIONS\n" if certs && certs.length > 0
    certs.each do |cert|
      ctitle = cert.at_css(".item-title")
      csub = cert.at_css(".item-subtitle")
      cdates = cert.at_css(".date-range")
      text_resume += "\n#{ctitle.text}\n" if ctitle
      text_resume += "#{csub.text}\n" if csub
      text_resume += "#{cdates.text}\n" if cdates
    end
    interests = page.css("#interests .pills .interest")
    text_resume += "\nINTERESTS\n" if interests && interests.length > 0
    ints = []
    interests.each do |interest|
      int = interest.at_css(".wrap")&.text
      if int
        ints << int unless (int == "See less") || (int.match(/See \d+\+/))
      end
    end
    text_resume += "#{ints.join(", ")}\n\n"
    skills = page.css("#skills .pills .skill")
    text_resume += "\n\nSKILLS\n" if skills && skills.length > 0
    sks = []
    skills.each do |skill|
      sk = skill.at_css(".wrap")&.text
      if sk
        sks << sk unless (sk == "See less") || (sk.match(/See \d+\+/))
      end
    end
    text_resume += "#{sks.join(", ")}\n\n"
    languages = page.css("#languages .language")
    text_resume += "\n\nLANGUAGES\n" if languages.length > 0
    langs = []
    languages.each do |language|
      lang = language.at_css(".name")&.text
      prof = language.at_css(".proficiency")
      lang += " (#{prof.text})" if prof && prof.text.length > 0
      langs << lang if lang
    end
    text_resume += "#{langs.join(", ")}\n\n"
    projects = page.css("#projects .project")
    text_resume += "\n\nPROJECTS\n" if projects && projects.length > 0
    projects.each do |project|
      ptitle = project.at_css(".item-title")
      pdates = project.at_css(".date-range")
      pdesc = project.at_css(".description")
      pdesc.css('br').each{|br| br.replace "\n"} if pdesc
      pcont = project.at_css(".contributors")
      text_resume += "\n#{ptitle.text}\n" if ptitle
      text_resume += "#{pdates.text}\n" if pdates
      text_resume += "#{pdesc.text}\n" if pdesc
      text_resume += "#{pcont.text}\n " if pcont
    end
    pubs = page.css("#publications .publication")
    text_resume += "\n\nPUBLICATIONS\n" if pubs && pubs.length > 0
    pubs.each do |pub|
      pubtitle = pub.at_css(".item-title")
      pubsub = pub.at_css(".item-subtitle")
      pubdates = pub.at_css(".date-range")
      pubdesc = pub.at_css(".description")
      pubdesc.css('br').each{|br| br.replace "\n"} if pubdesc
      pubcont = pub.at_css(".contributors")
      text_resume += "\n#{pubtitle.text}\n" if pubtitle
      text_resume += "#{pubsub.text}\n" if pubsub
      text_resume += "#{pubdates.text}\n" if pubdates
      text_resume += "#{pubdesc.text}\n" if pubdesc
      text_resume += "#{pubcont.text}\n" if pubcont
    end
    vols = page.css("#volunteering .position")
    text_resume += "\n\nVOLUNTEERING\n" if vols && vols.length > 0
    vols.each do |vol|
      voltitle = vol.at_css(".item-title")
      volsub = vol.at_css(".item-subtitle")
      voldates = vol.at_css(".date-range")
      voldesc = vol.at_css(".description")
      voldesc.css('br').each{|br| br.replace "\n"} if voldesc
      volcause = vol.at_css(".cause")
      text_resume += "\n#{voltitle.text}\n" if voltitle
      text_resume += "#{volsub.text}\n" if volsub
      text_resume += "#{voldates.text}\n" if voldates
      text_resume += "Cause: #{volcause.text}\n" if volcause
      text_resume += "#{voldesc.text}\n" if voldesc
    end
    orgs = page.css("#organizations li")
    text_resume += "\n\nORGANIZATIONS\n" if orgs && orgs.length > 0
    orgs.each do |org|
      orgtitle = org.at_css(".item-title")
      orgsub = org.at_css(".item-subtitle")
      orgdates = org.at_css(".date-range")
      orgdesc = org.at_css(".description")
      orgdesc.css('br').each{|br| br.replace "\n"} if orgdesc
      text_resume += "\n#{orgtitle.text}\n" if orgtitle
      text_resume += "#{orgsub.text}\n" if orgsub
      text_resume += "#{orgdates.text}\n" if orgdates
      text_resume += "#{orgdesc.text}\n" if orgdesc
    end
    pats = page.css("#patents .patent")
    text_resume += "\n\nPATENTS\n" if pats && pats.length > 0
    pats.each do |pat|
      pattitle = pat.at_css(".item-title")
      patsub = pat.at_css(".item-subtitle")
      patdates = pat.at_css(".date-range")
      patdesc = pat.at_css(".description")
      patdesc.css('br').each{|br| br.replace "\n"} if patdesc
      patcont = pat.at_css(".contributors")
      text_resume += "\n#{pattitle.text}\n" if pattitle
      text_resume += "#{patsub.text}\n" if patsub
      text_resume += "#{patdates.text}\n" if patdates
      text_resume += "#{patdesc.text}\n" if patdesc
      text_resume += "#{patcont.text}\n" if patcont
    end
    awards = page.css("#awards .award")
    text_resume += "\n\nAWARDS\n" if awards && awards.length > 0
    awards.each do |award|
      atitle = award.at_css(".item-title")
      asub = award.at_css(".item-subtitle")
      adates = award.at_css(".date-range")
      adesc = award.at_css(".description")
      adesc.css('br').each{|br| br.replace "\n"} if adesc
      text_resume += "\n#{atitle.text}\n" if atitle
      text_resume += "#{asub.text}\n" if asub
      text_resume += "#{adates.text}\n" if adates
      text_resume += "#{adesc.text}\n" if adesc
    end
    courses = page.css("#courses li")
    text_resume += "\n\nCOURSES\n" if courses && courses.length > 0
    courses.each do |course|
      coutitle = course.at_css(".item-title")
      coulist = course.at_css(".courses-list")
      text_resume += "\n#{coutitle.text}\n" if coutitle
      text_resume += "#{coulist.text}\n" if coulist
    end


    row["Contact ID"] = contact_id
    row["CV TR"] = "1"
    row["Account Name"] = acc_name
    row["Linkedin Import Status"] = import_status
    row["First Name"] = name[0]&.slice(0, 39)
    row["Last Name"] = name[1..-1]&.join(" ")&.slice(0, 79)
    row["Email"] = email
    row["Candidate ID"] = cand_id
    row["LIN 1st Degree"] = cand_source
    row["Title"] = title&.slice(0, 127)
    row["Contact Country"] = country
    row["Contact LIN Sector"] = sector&.slice(0, 99)
    row["Employer 1 Title"] = e1_title&.slice(0, 31999)
    row["Employer Organization Name 1"] = e1_org&.slice(0, 254)
    row["Employer 1 Start Date"] = format_date(e1_start) #format
    row["Employer 1 End Date"] = format_date(e1_end) #format
    row["Employer 1 Location"] = e1_loc&.slice(0, 254)
    row["Employer 1 Description"] = e1_desc&.slice(0, 31999)
    row["Employer 2 Title"] = e2_title&.slice(0, 31999)
    row["Employer Organization Name 2"] = e2_org&.slice(0, 254)
    row["Employer 2 Start Date"] = format_date(e2_start) #format
    row["Employer 2 End Date"] = format_date(e2_end) #format
    row["Employer 2 Location"] = e2_loc&.slice(0, 254)
    row["Employer 2 Description"] = e2_desc&.slice(0, 31999)
    row["Employer 3 Title"] = e3_title&.slice(0, 31999)
    row["Employer Organization Name 3"] = e3_org&.slice(0, 254)
    row["Employer 3 Start Date"] = format_date(e3_start) #format
    row["Employer 3 End Date"] = format_date(e3_end) #format
    row["Employer 3 Location"] = e3_loc&.slice(0, 254)
    row["Employer 3 Description"] = e3_desc&.slice(0, 31999)
    row["License or Certification Name 1"] = c1_name&.slice(0, 254)
    row["License or Certification Name 2"] = c2_name&.slice(0, 254)
    row["License or Certification Credential Type"] = c_type&.slice(0, 254)
    row["Education School 1"] = s1_name&.slice(0, 124)
    row["Education Degree Name 1"] = s1_degree&.slice(0, 254)
    row["Education Degree Date 1"] = format_date(s1_end)
    row["Education School 2"] = s2_name&.slice(0, 124)
    row["Education Degree Name 2"] = s2_degree&.slice(0, 254)
    row["Education Degree Date 2"] = format_date(s2_end)
    row["Text Resume"] = text_resume&.slice(0, 31999)
    row["LinkedIn Profile"] = lin_profile&.slice(0, 254)
    row["Resume Last Updated"] = Time.now.strftime('%Y-%m-%d %H:%M:%S')
    row["LIN Import Date"] = Time.now.strftime('%Y-%m-%d')
    row["CV Uploaded"] = "1"

    if mode == 'update'
      if @options[:update]
        puts "outputting update"
        append_to_csv(@output_update, row)
      end
    elsif mode == 'insert'
      if @options[:insert]
        puts "outputting insert"
        append_to_csv(@output_insert, row)
      end
    end

  end

  # def scrape_education(input_row, page)
  #   schools = page.css("#education .schools .school")
  #
  #   schools.each do |school|
  #     row = CSV::Row.new(@education_headers, [])
  #     row["Contact"] = input_row[]
  #     row["School Name"] = school.at_css(".item-title").text.slice(0, 149)
  #     row["Major"] = school.at_css(".item-subtitle").text.slice(0, 254)
  #     dstart = school.css(".date-range time")[0]
  #     dend = school.css(".date-range time")[1]
  #     if dend
  #       row["Graduation Year"] = dend.text.gsub(/\D/, '').slice(0, 74)
  #     else
  #       row["Graduation Year"] = dstart.text.gsub(/\D/, '').slice(0, 74)
  #     end
  #     rows << row
  #   end
  #   return rows
  # end
  #
  # def scrape_employment(row, page)
  #
  # end

  def format_date(input_date)
    if input_date.nil?
      return nil
    end
    begin
      date_arr = input_date.split(" ")
      if date_arr.length == 1
        output_date = Date.strptime(input_date, "%Y")
        return output_date.strftime("%Y-%m-%d")
      elsif date_arr.length == 2
        output_date = Date.strptime(input_date, "%B %Y")
        return output_date.strftime("%Y-%m-%d")
      else
        return nil
      end
    rescue
      if date_arr.length == 2
        return format_date(date_arr[1])
      else
        return nil
      end
    end
  end

  def validate(url, row)
    puts "url: #{url}"
    begin
      agent = Mechanize.new

      unless @noproxy
        proxy = @proxies.get_proxy
        agent.set_proxy(proxy.ip, proxy.port, proxy.username, proxy.password)
        agent.user_agent = proxy.user_agent
        puts "proxy: #{proxy.ip}"
      end
      sleep(@cooldown) if @noproxy
      page = agent.get(url)
      puts 'ACCESS GRANTED'

      return false unless page.at_css("#name") && page.css("#experience .positions .position")
      return false unless name_check(page.at_css("#name").text, "#{row['First Name']} #{row['Last Name']}")
      positions = page.css("#experience .positions .position")

      match = false
      positions.each do |position|
        if position.at_css("header .item-title a") && position.at_css("header .item-subtitle")
          profile_title = I18n.transliterate(position.at_css("header .item-title a").text).alnum
          profile_employer = I18n.transliterate(position.at_css("header .item-subtitle").text).alnum
          title = I18n.transliterate(row['Employer 1 Title']).alnum
          employer = I18n.transliterate(row['Employer Organization Name 1']).alnum
          if name_check(profile_title, title) && name_check(profile_employer, employer)
            match = true
          end
        end
      end
      proxy.good if proxy
      if match
        return [url, page]
      else
        return false
      end
    rescue StandardError => e
      puts e
      if e.to_s.start_with?('999')
        proxy.dead if proxy
        retry
      elsif e.to_s.start_with?('404') || e.to_s.start_with?('403')
        proxy.good if proxy
        return false
      else
        puts e.backtrace
        proxy.used if proxy
        retry
      end
    end
  end

  def start
    count = 0
    CSV.foreach(@input_file, headers: true) do |input_row|
      count += 1
      next if @start && @start >= count
      tries = @proxies.length unless @noproxy
      puts "lin #{count}/#{@input_length}"
      # begin
        urls = input_row['Urls']
        if urls && urls.include?('http')
          urls = urls.split(', ')
          correct_url, correct_page = nil
          urls.each do |url|
            correct_url, correct_page = validate(url, input_row)
            break if correct_url && correct_page
          end
          if correct_url
            puts "correct page"
            input_row << ["Linkedin Profile", correct_url]
            input_row["Linkedin Import Status"] = 'Profile imported'
            input_row.delete('Urls')
            if input_row['Contact ID'] && input_row['Contact ID'].strip.length > 0
              scrape_contact(input_row, correct_page, 'update') if @options[:update]
            else
              scrape_contact(input_row, correct_page, 'insert') if @options[:insert]
            end
            # scrape_employment(input_row, correct_page)
            # scrape_education(input_row, correct_page)
          else
            if @options[:update] && input_row['Contact ID'] && input_row['Contact ID'].strip.length > 0
              input_row << ["Linkedin Profile", nil]
              input_row.delete('Urls')
              input_row["Linkedin Import Status"] = 'Profile not found'
              output_row = create_row(input_row, @headers)
              puts "outputting update"
              puts input_row["Linkedin Import Status"]
              append_to_csv(@output_update, output_row)
            elsif @options [:insert]
              input_row << ["Linkedin Profile", nil]
              input_row.delete('Urls')
              input_row["Linkedin Import Status"] = 'Profile not found'
              puts "outputting insert"
              puts input_row["Linkedin Import Status"]
              output_row = create_row(input_row, @headers)
              append_to_csv(@output_insert, output_row)
            end
          end
        else
          if @options[:update] && input_row['Contact ID'] && input_row['Contact ID'].strip.length > 0
            input_row << ["Linkedin Profile", nil]
            input_row.delete('Urls')
            puts "outputting update"
            puts input_row["Linkedin Import Status"]
            output_row = create_row(input_row, @headers)
            append_to_csv(@output_update, output_row)
          elsif @options [:insert]
            input_row << ["Linkedin Profile", nil]
            input_row.delete('Urls')
            puts "outputting insert"
            puts input_row["Linkedin Import Status"]
            output_row = create_row(input_row, @headers)
            append_to_csv(@output_insert, output_row)
          end
        end
      # rescue Exception => msg
      #   tries -= 1
      #   if tries > 0
      #     puts "\n\n"
      #     puts msg
      #     puts 'RETRYING'
      #     puts "\n\n"
      #     if msg.to_s.start_with?("999")
      #       proxy.dead
      #     else
      #       proxy.used
      #     end
      #     retry
      #   else
      #     #append_ddg_row(input_row, msg, nil)
      #     puts msg
      #   end
      # end
    end

  end

end
