
require 'linkeddata'
require 'edtf'

EDTFi = EDTF

module Solis
  class Model
    module Literal

      class EDTF < RDF::Literal
        DATATYPE = RDF::URI('http://id.loc.gov/datatypes/edtf/EDTF')
        def valid?
          v = EDTFi.parse(value)
          v.nil? ? false : true
        end
      end

    end
  end
end
