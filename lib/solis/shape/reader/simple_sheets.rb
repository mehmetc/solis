require 'google/apis/sheets_v4'
require_relative 'simple_sheets/sheet'
require_relative 'simple_sheets/worksheet'

class SimpleSheets
  attr_accessor :key
  attr_reader :sheets_service, :id

  def initialize(key, spreadsheet_id)
    @id = spreadsheet_id
    @key = key
    @sheets_service = Google::Apis::SheetsV4::SheetsService.new
    @sheets_service.key = @key    
  end

  def worksheets
    spreadsheet_api = @sheets_service.get_spreadsheet(@id, fields: 'sheets.properties')
    spreadsheet_api.sheets.map { |s| Worksheet.new(self, s.properties) }
    #TODO: catch not found
  end

  def worksheet_by_title(title)
    worksheets.find { |ws| ws.title == title }
  end

  def worksheet_by_sheet_id(sheet_id)
    sheet_id = sheet_id.to_i
    worksheets.find { |ws| ws.sheet_id == sheet_id }
  end

end
