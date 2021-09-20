  class Worksheet
    attr_reader :properties, :title, :spreadsheet

    def initialize(spreadsheet, properties)
      @spreadsheet = spreadsheet
      set_properties(properties)
      @cells = nil
      @input_values = nil
      @numeric_values = nil
      @modified = Set.new
    end

    def sheet_id
      @properties.sheet_id
    end

    def gid
      sheet_id.to_s
    end

    def [](*args)
      (row, col) = parse_cell_args(args)
      cells[[row, col]] || ''
    end

    def rows(skip = 0)
      nc = num_cols
      result = ((1 + skip)..num_rows).map do |row|
        (1..nc).map { |col| self[row, col] }.freeze
      end
      result.freeze
    end

    def num_rows
      reload_cells unless @cells
      # Memoizes it because this can be bottle-neck.
      # https://github.com/gimite/google-drive-ruby/pull/49
      @num_rows ||=
        @input_values
          .reject { |(_r, _c), v| v.empty? }
          .map { |(r, _c), _v| r }
          .max ||
          0
    end

    # Column number of the right-most non-empty column.
    def num_cols
      reload_cells unless @cells
      # Memoizes it because this can be bottle-neck.
      # https://github.com/gimite/google-drive-ruby/pull/49
      @num_cols ||=
        @input_values
          .reject { |(_r, _c), v| v.empty? }
          .map { |(_r, c), _v| c }
          .max ||
          0
    end

    private
    def parse_cell_args(args)
      if args.size == 1 && args[0].is_a?(String)
        cell_name_to_row_col(args[0])
      elsif args.size == 2 && args[0].is_a?(Integer) && args[1].is_a?(Integer)
        if args[0] >= 1 && args[1] >= 1
          args
        else
          raise(
            ArgumentError,
            format(
              'Row/col must be >= 1 (1-origin), but are %d/%d',
              args[0], args[1]
            )
          )
        end
      else
        raise(
          ArgumentError,
          format(
            "Arguments must be either one String or two Integer's, but are %p",
            args
          )
        )
      end
    end

    def cell_name_to_row_col(cell_name)
      unless cell_name.is_a?(String)
        raise(
          ArgumentError, format('Cell name must be a string: %p', cell_name)
        )
      end
      unless cell_name.upcase =~ /^([A-Z]+)(\d+)$/
        raise(
          ArgumentError,
          format(
            'Cell name must be only letters followed by digits with no ' \
            'spaces in between: %p',
            cell_name
          )
        )
      end
      col = 0
      Regexp.last_match(1).each_byte do |b|
        # 0x41: "A"
        col = col * 26 + (b - 0x41 + 1)
      end
      row = Regexp.last_match(2).to_i
      [row, col]
    end

    def cells
      reload_cells unless @cells
      @cells
    end

    def set_properties(properties)
      @properties = properties
      @title = @remote_title = properties.title
      @index = properties.index
      if properties.grid_properties.nil?
        @max_rows = @max_cols = 0
      else
        @max_rows = properties.grid_properties.row_count
        @max_cols = properties.grid_properties.column_count
      end
      @meta_modified = false
    end

    def reload_cells
      response =
        @spreadsheet.sheets_service.get_spreadsheet(
          @spreadsheet.id,
          ranges: "'%s'" % @remote_title,
          fields: 'sheets.data.rowData.values(formattedValue,userEnteredValue,effectiveValue)'
        )
      update_cells_from_api_sheet(response.sheets[0])
    end

    def update_cells_from_api_sheet(api_sheet)
      rows_data = api_sheet.data[0].row_data || []

      @num_rows = rows_data.size
      @num_cols = 0
      @cells = {}
      @input_values = {}
      @numeric_values = {}

      rows_data.each_with_index do |row_data, r|
        next if !row_data.values
        @num_cols = row_data.values.size if row_data.values.size > @num_cols
        row_data.values.each_with_index do |cell_data, c|
          k = [r + 1, c + 1]
          @cells[k] = cell_data.formatted_value || ''
          @input_values[k] = extended_value_to_str(cell_data.user_entered_value)
          @numeric_values[k] =
            cell_data.effective_value && cell_data.effective_value.number_value ?
              cell_data.effective_value.number_value.to_f : nil
        end
      end

      @modified.clear
    end

    def extended_value_to_str(extended_value)
      return '' if !extended_value
      value =
        extended_value.number_value ||
          extended_value.string_value ||
          extended_value.bool_value ||
          extended_value.formula_value
      value.to_s
    end
  end