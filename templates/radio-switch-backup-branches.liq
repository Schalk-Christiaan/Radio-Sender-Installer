      ({source_override() == "rugsteun" and backup_radio_connected()}, backup_radio),
      ({source_override() == "" and primary_source == "1" and backup_radio_connected()}, backup_radio),
      ({source_override() == "" and primary_source == "2" and backup_radio_connected()}, backup_radio),
      ({source_override() == "" and primary_source == "2" and radio_connected()}, radio),
