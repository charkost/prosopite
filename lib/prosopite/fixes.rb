module Prosopite
  # Suggests fixes for an N+1 from the associations that run queries like its own:
  # on the table of the associated model, by the foreign key of the association,
  # or by the primary key for belongs_to
  module Fixes
    TABLE = /\bFROM\s+[`"]?(\w+)[`"]?/i
    COLUMN = /\bWHERE\s+(?:[`"]?\w+[`"]?\.)?[`"]?(\w+)[`"]?\s*(?:=|IN\b)/i
    COUNT = /\A\s*SELECT\s+COUNT\(/i
    EXISTS = /\A\s*SELECT\s+1\s+AS\s+one\b/i

    class << self
      # The block can return where the records of a model were loaded
      def for(query, index = self.index)
        associations(query, index).map do |reflection|
          owner = reflection.active_record
          fix = "#{owner.name}.includes(:#{reflection.name})"
          location = yield(owner) if block_given?
          fix += " where the #{owner.table_name} are loaded, at #{location}" if location

          if query.match?(COUNT)
            "#{fix}, then #{reflection.name}.size; or a counter cache"
          elsif query.match?(EXISTS)
            "#{fix}, then #{reflection.name}.any?"
          else
            fix
          end
        end
      end

      def associations(query, index = self.index)
        table = query[TABLE, 1]
        column = query[COLUMN, 1]
        return [] unless table && column

        index.fetch([table, column], [])
      end

      # The associations by the table and the column of their queries, built again
      # only when the models change, e.g. when reloading code in development
      def index
        models = ActiveRecord::Base.descendants
        models_key = models.map(&:object_id)
        return @index if @index_models_key == models_key

        index = {}
        models.flat_map(&:reflect_on_all_associations).uniq.each do |reflection|
          key = query_key(reflection)
          (index[key] ||= []) << reflection if key
        end
        @index_models_key = models_key
        @index = index
      end

      private

      def query_key(reflection)
        return if reflection.through_reflection? || reflection.polymorphic? || reflection.active_record.name.nil?

        column = reflection.belongs_to? ? reflection.association_primary_key : reflection.foreign_key
        [reflection.klass.table_name, column.to_s]
      rescue NameError
        # The class of the association doesn't exist
        nil
      end
    end
  end
end
