module Prosopite
  # Suggests fixes for an N+1 from the associations that run queries like its own:
  # on the table of the associated model, by the foreign key of the association,
  # or by the primary key for belongs_to
  module Fixes
    TABLE = /\bFROM\s+[`"]?(\w+)[`"]?/i
    COLUMN = /\bWHERE\s+(?:[`"]?\w+[`"]?\.)?[`"]?(\w+)[`"]?\s*(?:=|IN\b)/i

    class << self
      def for(query)
        associations(query).map do |reflection|
          includes = "#{reflection.active_record.name}.includes(:#{reflection.name})"

          if query.match?(/\A\s*SELECT\s+COUNT\(/i)
            "#{includes} and #{reflection.name}.size, or a counter cache"
          elsif query.match?(/\A\s*SELECT\s+1\s+AS\s+one\b/i)
            "#{includes} and #{reflection.name}.any?"
          else
            includes
          end
        end
      end

      def associations(query)
        table = query[TABLE, 1]
        column = query[COLUMN, 1]
        return [] unless table && column

        reflections = ActiveRecord::Base.descendants.flat_map(&:reflect_on_all_associations).uniq
        reflections.select { |reflection| runs_query?(reflection, table, column) }
      end

      private

      def runs_query?(reflection, table, column)
        return false if reflection.through_reflection? || reflection.polymorphic? || reflection.active_record.name.nil?

        key = reflection.belongs_to? ? reflection.association_primary_key : reflection.foreign_key
        reflection.klass.table_name == table && key.to_s == column
      rescue NameError
        # The class of the association doesn't exist
        false
      end
    end
  end
end
