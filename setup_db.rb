#!/usr/bin/env ruby

# Customize the following if you want to use MySQL or something.
DB = Sequel.sqlite 'db.sqlite'
# DB = Sequel.connect('postgres://user:password@localhost/my_db')
# DB = Sequel.connect('mysql://user:password@localhost/my_db')

begin
  DB.create_table :stats do
    primary_key :id
    DateTime :timestamp
    String :board
    Float :pps
  end
rescue Exception
  # should already exist
end
