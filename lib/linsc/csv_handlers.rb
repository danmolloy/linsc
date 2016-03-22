module CSVHandlers
  def create_row(row, headers, encoding = nil)
    values = []
    headers.each do |header|
      if encoding
        values << row[header]&.encode(encoding)
      else
        values << row[header]
      end
    end
    CSV::Row.new(headers, values)
  end

  def append_to_csv(file, row)
    f = CSV.open(file, "a+", headers: row.headers, force_quotes: true)
    f << row
    f.close
  end

  def create_file(f)
    unless File.exist?(f)
      FileUtils.touch(f)
      csv = CSV.open(f, "w+")
      csv << @headers.collect {|x| x&.encode('utf-8')}
      csv.close
    end
  end

  def create_file_with_headers(f, headers)
    unless File.exist?(f)
      FileUtils.touch(f)
      csv = CSV.open(f, "w+")
      csv << headers.collect {|x| x&.encode('utf-8')}
      csv.close
    end
  end

  def get_headers(file)
    CSV.open(file, headers: true, return_headers: true).shift.headers
  end
end
