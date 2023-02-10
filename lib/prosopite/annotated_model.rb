module Prosopite
  module AnnotatedModel
    extend ActiveSupport::Concern

    ANNOTATION = '!prosopite:ignore!'
    ANNOTATION_COMMENT = "/* #{ANNOTATION} */".freeze

    class_methods do
      def prosopite_ignore
        annotate(ANNOTATION)
      end
    end

    def self.ignored?(sql)
      sql.include? ANNOTATION_COMMENT
    end
  end
end
