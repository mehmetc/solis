

module Solis
  class Store

    module SaveMode
      PRE_DELETE_PEERS = 0
      PRE_DELETE_PEERS_IF_DIFF_SET = 1
      APPEND_IF_NOT_PRESENT = 2
    end

    module DeleteMode
      DELETE_ATTRIBUTE = 3
    end

  end
end