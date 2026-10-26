module Prosopite
  # Suggests fixes for an N+1 from the associations whose loading runs queries like its
  # own: on the table of the associated model, with a single condition on the foreign key
  # of the association, or on the primary key for belongs_to. Other queries, like ones
  # with more conditions, aggregates or joins, run whether an association is loaded or not.
  module Fixes
    # Comments before the query, e.g. of query_log_tags
    LEADING_COMMENTS = %r{\A\s*(?:/\*.*?\*/\s*)+}m
    QUERY = /\A
      SELECT\s+(?<select>.+?)\s+
      FROM\s+(?<table>[`"]?\w+[`"]?)\s+
      WHERE\s+(?<column>(?:[`"]?\w+[`"]?\.)?[`"]?\w+[`"]?)\s*
      (?:=\s*(?:\$\d+|\?|-?\d+|'[^']*'|:\w+)|IN\s*\([^()]*\))
      (?:\s+ORDER\s+BY\s+[^;]+?)?
      (?:\s+LIMIT\s+\S+)?
      (?:\s+OFFSET\s+\S+)?
      \s*;?\s*
    \z/xim
    COLUMN = /(?:[`"]?\w+[`"]?\.)?[`"]?\w+[`"]?/
    # Associations that can't be told apart without where their records were loaded
    MAX_AMBIGUOUS = 3

    class << self
      # The block returns [order, location] for where records of a model were loaded, with
      # order telling how recent that was, to pick the associations of the records looped on
      def for(query, index = self.index)
        match = parse(query)
        kind = match && kind(match[:select])
        return [] unless kind

        reflections = associations(query, index).select { |reflection| kind == :load || reflection.collection? }
        loads = reflections.to_h { |reflection| [reflection, block_given? ? yield(reflection.active_record) : nil] }
        latest = loads.values.compact.map(&:first).max

        if latest
          reflections = reflections.select { |reflection| loads[reflection]&.first == latest }
        elsif reflections.size > MAX_AMBIGUOUS
          return []
        end

        reflections.map { |reflection| suggestion(reflection, kind, loads[reflection]&.last) }
      end

      def associations(query, index = self.index)
        match = parse(query)
        return [] unless match

        table = unquote(match[:table])
        qualifier, column = match[:column].split('.', 2).map { |name| unquote(name) }
        qualifier, column = nil, qualifier unless column
        return [] if qualifier && qualifier != table

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
        @index = index
        @index_models_key = models_key
        index
      end

      private

      def parse(query)
        query.sub(LEADING_COMMENTS, '').match(QUERY)
      end

      def kind(select)
        if select.match?(/\A(?:[`"]?\w+[`"]?\.)?\*\z/)
          :load
        elsif select.match?(/\ACOUNT\(/i)
          :count
        elsif select.match?(/\A1 AS one\z/i)
          :exists
        elsif select.match?(/\A#{COLUMN}(?:\s*,\s*#{COLUMN})*\z/)
          # pluck, which uses the records of a loaded association
          :load
        end
      end

      def suggestion(reflection, kind, location)
        owner = reflection.active_record
        fix = "#{owner.name}.includes(:#{reflection.name})"
        fix += " where the #{owner.table_name} are loaded, at #{location}" if location

        case kind
        when :count then "#{fix}, then #{reflection.name}.size; or a counter cache"
        when :exists then "#{fix}, then #{reflection.name}.any?"
        else fix
        end
      end

      def unquote(name)
        name.delete('`"')
      end

      def query_key(reflection)
        owner = reflection.active_record.name
        # Through associations join, and Rails defines HABTM_ models for its join tables
        return if reflection.through_reflection? || reflection.polymorphic? || owner.nil? || owner.include?('HABTM_')

        column = reflection.belongs_to? ? reflection.association_primary_key : reflection.foreign_key
        [reflection.klass.table_name, column.to_s]
      rescue NameError
        # The class of the association doesn't exist
        nil
      end
    end

    # Where the records that N+1s loop on were loaded: the last query on their table before
    # each N+1, with its order among the queries of the scan
    class Loads
      def initialize(state, backtrace_cleaner)
        @holder = state[:prosopite_query_holder]
        @callers = state[:prosopite_query_caller]
        @backtrace_cleaner = backtrace_cleaner
        # In the order of their first query. A copy, as an ActionController::Live action may
        # still be adding to them.
        @keys = @holder.keys
        @positions = @keys.each_with_index.to_h
        @found = {}
      end

      def at(location_key, table)
        @found.fetch([location_key, table]) { |key| @found[key] = find(location_key, table) }
      end

      private

      def find(location_key, table)
        from_table = /\bFROM\s+[`"]?#{Regexp.escape(table)}[`"]?(?:\s|\z)/i
        (@positions.fetch(location_key, @keys.size) - 1).downto(0) do |position|
          key = @keys[position]
          next unless @holder[key].first.match?(from_table)

          # The call stacks of single queries are kept up to a limit
          caller = @callers[key]
          frame = caller && @backtrace_cleaner.clean(caller.map(&:to_s)).first
          return [position, frame&.sub(/:in\b.*\z/, '')]
        end

        nil
      end
    end
  end
end
