#!/usr/bin/env sysbench
-- Copyright (C) 2006-2017 Alexey Kopytov <akopytov@gmail.com>

-- This program is free software; you can redistribute it and/or modify
-- it under the terms of the GNU General Public License as published by
-- the Free Software Foundation; either version 2 of the License, or
-- (at your option) any later version.

-- This program is distributed in the hope that it will be useful,
-- but WITHOUT ANY WARRANTY; without even the implied warranty of
-- MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
-- GNU General Public License for more details.

-- You should have received a copy of the GNU General Public License
-- along with this program; if not, write to the Free Software
-- Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA

-- ----------------------------------------------------------------------
-- Insert-Only OLTP benchmark
-- ----------------------------------------------------------------------

require("oltp_common")

cursize = sysbench.tid + 1
line_number = 2

sysbench.cmdline.commands.prepare = {
   function ()
      if (not sysbench.opt.auto_inc) then
         -- Create empty tables on prepare when --auto-inc is off, since IDs
         -- generated on prepare may collide later with values generated by
         -- sysbench.rand.unique()
         sysbench.opt.table_size=0
      end

      local drv = sysbench.sql.driver()
      local con = drv:connect()

      for table_num = sysbench.tid % sysbench.opt.threads + 1, sysbench.opt.tables,
      sysbench.opt.threads do
         local id_index_def, id_def
         local engine_def = ""
         local query

         if sysbench.opt.secondary then
            id_index_def = "KEY xid"
         else
            id_index_def = "PRIMARY KEY"
         end

         if drv:name() == "mysql"
         then
            if sysbench.opt.auto_inc then
               id_def = "INTEGER NOT NULL AUTO_INCREMENT"
            else
               id_def = "INTEGER NOT NULL"
            end
            engine_def = "/*! ENGINE = " .. sysbench.opt.mysql_storage_engine .. " */"
         elseif drv:name() == "pgsql"
         then
            if not sysbench.opt.auto_inc then
               id_def = "INTEGER NOT NULL"
            elseif pgsql_variant == 'redshift' then
               id_def = "INTEGER IDENTITY(1,1)"
            else
               id_def = "SERIAL"
            end
         else
            error("Unsupported database driver:" .. drv:name())
         end

         print(string.format("Creating table 'sbtest%d'...", table_num))

         local formatString = [[
CREATE TABLE sbtest%d(
  id %s,
  k INTEGER DEFAULT '0' NOT NULL,
]]
         for i = 1, line_number do
            formatString = formatString .. "  pad" .. i .. " CHAR(60) DEFAULT '' NOT NULL,\n"
         end
         formatString = formatString .. [[
  %s (id)
) ]]

         query = string.format(formatString,
                 table_num, id_def, id_index_def)

         print(query)
         print(sysbench.opt.table_size)
         con:query(query)

         if (sysbench.opt.table_size > 0) then
            print(string.format("Inserting %d records into 'sbtest%d'",
                    sysbench.opt.table_size, table_num))
         end

         if sysbench.opt.auto_inc then
            query = "INSERT INTO sbtest" .. table_num .. "(k"
            for i = 1, line_number do
               query = query .. ", pad" .. i
            end
            query = query .. ") VALUES"
         else
            query = "INSERT INTO sbtest" .. table_num .. "(id, k"
            for i = 1, line_number do
               query = query .. ", pad" .. i
            end
            query = query .. ") VALUES"
         end

         con:bulk_insert_init(query)

         local c_val
         local pad_val

         for i = 1, sysbench.opt.table_size do

            c_val = get_c_value()
            pad_val = get_pad_value()

            if (sysbench.opt.auto_inc) then
               query = "(" .. sysbench.rand.default(1, sysbench.opt.table_size)
            else
               query = "(" .. i .. ", " .. sysbench.rand.default(1, sysbench.opt.table_size)
            end
            for i = 1, line_number do
               query = query .. ", '" .. get_pad_value() .. "'"
            end
            query = query .. ")"
            con:bulk_insert_next(query)
         end

         con:bulk_insert_done()

         if sysbench.opt.create_secondary then
            print(string.format("Creating a secondary index on 'sbtest%d'...",
                    table_num))
            con:query(string.format("CREATE INDEX k_%d ON sbtest%d(k)",
                    table_num, table_num))
         end
      end
   end,
   sysbench.cmdline.PARALLEL_COMMAND
}

function prepare_statements()
   -- We do not use prepared statements here, but oltp_common.sh expects this
   -- function to be defined
end

function event()
   local table_name = "sbtest1"
   -- local k_val = sysbench.rand.default(1, sysbench.opt.table_size)
   local k_val = sysbench.tid + 1

   if (cursize <= sysbench.opt.threads) then
      con:bulk_insert_init("INSERT INTO " .. table_name .. " VALUES")
   end

   local insert_sql = "(" .. cursize .. ", " .. k_val
   for i = 1, line_number do
      insert_sql = insert_sql .. ", '" .. get_pad_value() .. "'"
   end
   insert_sql = insert_sql .. ")"

   con:bulk_insert_next(insert_sql)

   cursize = cursize + sysbench.opt.threads


end