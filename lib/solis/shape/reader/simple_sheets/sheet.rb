class Sheet
  include Enumerable
  def initialize(worksheet)
    @worksheet = worksheet
    @last_sync = Time.now
  end

  def title
    @worksheet.title
  end

  def each
    @worksheet.rows(skip=1).each do |row|
      yield make_record_from_row(row)
    end
  end

  def header
    @header ||= @worksheet.rows[0].map{|m| m.downcase.gsub(' ','_').gsub('#', '_hash').gsub('%','_percent')}
  end

  def [](index)
    row_as_record(@worksheet.rows(skip=0)[index])
  end

  def count
    @worksheet.num_rows - 1
  end

  private
  def sync
    if (Time.now.to_i - @last_sync.to_i) > 600
      @worksheet.synchronize
    end
  end

  def row_as_record(row)
    sync
    result = []
    return result if row.nil?
    if row && row.is_a?(Array) && row.first.is_a?(Array)
      result = row.map do |m|
        m.is_a?(Array) ? make_record_from_row(m) : m
      end
    else
      result = make_record_from_row(row)
    end
    result
  end

  def make_record_from_row(row)
    return nil if row.nil?
    result = {}
    row.each_index do |i|
      result.store(self.header[i], row[i])
    end
    result
  end
end
