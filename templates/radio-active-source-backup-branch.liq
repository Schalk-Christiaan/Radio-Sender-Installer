    elsif source_override() == "rugsteun" and backup_radio.is_ready() then
      "rugsteun"
    elsif source_override() == "" and primary_source == "1" and backup_radio.is_ready() then
      "rugsteun"
    elsif source_override() == "" and primary_source == "2" and backup_radio.is_ready() then
      "rugsteun"
    elsif source_override() == "" and primary_source == "2" and radio.is_ready() then
      "primer"
