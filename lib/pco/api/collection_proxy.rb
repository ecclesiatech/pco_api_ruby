module PCO
  module API
    class CollectionProxy
      def initialize(connection:, path:, klass:, params:)
        @connection = connection
        @path = path
        @klass = klass
        @params = params
        @includes = {}
        @per_page = nil
        reset
      end

      attr_reader :connection, :path, :klass, :wrap_proc

      def includes(mappings)
        @includes.merge!(mappings)
        self
      end

      def per_page(number)
        @per_page = number
        self
      end

      def each
        loop do
          fetch_next if more?
          record = consume_and_transform
          break unless record
          yield record
        end
      end

      def to_a
        reset
        array = []
        each do |object|
          array << object
        end
        array
      end

      def first
        reset
        fetch_next
        consume_and_transform
      end

      def last
        reset
        meta = fetch_meta
        @offset = meta['total_count'] - 1
        fetch_next
        record = @response['data'].last
        return unless record
        transform(record)
      end

      private

      def consume_and_transform
        record = @response['data'].shift
        return unless record
        transform(record)
      end

      def transform(record)
        klass.build_object(record, included: @response['included'], include_mapping: @includes)
      end

      def reset
        @offset = nil
      end

      def more?
        return true unless @response
        @response['data'].empty? &&
          @response.fetch('meta', {}).fetch('next', {})['offset']
      end

      def params
        @params.dup.tap do |hash|
          hash[:per_page] = @per_page if @per_page
          hash[:offset] = @offset if @offset
          hash[:include] = @includes.keys.join(',') if @includes.any?
        end
      end

      def fetch_next
        @response = connection[path].get(params)
        @offset = @offset.to_i + 1
      rescue PCO::API::Errors::TooManyRequests => e
        sleep e.retry_after
        retry
      end

      def fetch_meta
        my_params = params.dup
        my_params.delete(:include)
        my_params[:per_page] = 0
        connection[path].get(my_params)['meta']
      end
    end
  end
end
