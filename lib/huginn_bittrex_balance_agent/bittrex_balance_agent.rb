module Agents
  class BittrexBalanceAgent < Agent
    include FormConfigurable

    can_dry_run!
    no_bulk_receive!
    default_schedule "never"

    description do
      <<-MD
      The Bittrex Balance agent fetches balances from Bittrex.

      `changes_only` is only used to emit event about a currency's change.

      `expected_receive_period_in_days` is used to determine if the Agent is working. Set it to the maximum number of days
      that you anticipate passing without this Agent receiving an incoming Event.
      MD
    end

    event_description <<-MD
      Events look like this:

          {
            "Currency": "BTC",
            "Balance": 100000.00079137,
            "Available": 100000.00079137,
            "Pending": 0.0,
            "CryptoAddress": "XXXXXXXXXXXXXXXXXXXXXXXXX"
          }
    MD

    def default_options
      {
        'debug' => 'false',
        'apikey' => '',
        'secret_key' => '',
        'expected_receive_period_in_days' => '2',
        'changes_only' => 'true'
      }
    end

    form_configurable :expected_receive_period_in_days, type: :string
    form_configurable :apikey, type: :string
    form_configurable :secret_key, type: :string
    form_configurable :changes_only, type: :boolean
    form_configurable :debug, type: :boolean
    def validate_options
      unless options['apikey'].present?
        errors.add(:base, "apikey is a required field")
      end

      unless options['secret_key'].present?
        errors.add(:base, "secret_key is a required field")
      end

      if options.has_key?('changes_only') && boolify(options['changes_only']).nil?
        errors.add(:base, "if provided, changes_only must be true or false")
      end

      if options.has_key?('debug') && boolify(options['debug']).nil?
        errors.add(:base, "if provided, debug must be true or false")
      end

      unless options['expected_receive_period_in_days'].present? && options['expected_receive_period_in_days'].to_i > 0
        errors.add(:base, "Please provide 'expected_receive_period_in_days' to indicate how many days can pass before this Agent is considered to be not working")
      end
    end

    def working?
      event_created_within?(options['expected_receive_period_in_days']) && !recent_error_logs?
    end

    def check
      fetch
    end

    private
    
    # Generate a continually-increasing unsigned 51-bit integer nonce from the
    # current Unix Time.
    #
    def generate_nonce
      (Time.now.to_f * 1000).to_i
    end

    def signature(url)
      ::OpenSSL::HMAC.hexdigest 'sha512', interpolated['secret_key'], url
    end

    def digest(body = nil)
      string =
        if body.is_a?(Hash)
          body.to_json
        elsif body.nil?
          ''
        end

      Digest::SHA512.hexdigest(string)
    end

    def fetch
      nonce = generate_nonce
      content_hash = digest
      url = "https://api.bittrex.com/v3/balances"
      presign = nonce.to_s + url + 'GET' + content_hash
      uri = URI.parse(url)
      request = Net::HTTP::Get.new(uri)
      request["Api-Key"] = interpolated['apikey']
      request["Api-Timestamp"] = nonce.to_s
      request["Api-Content-Hash"] = content_hash
      request["Api-Signature"] = signature(presign)
      
      req_options = {
        use_ssl: uri.scheme == "https",
      }

      response = Net::HTTP.start(uri.hostname, uri.port, req_options) do |http|
        http.request(request)
      end

      if interpolated['debug'] == 'true'
        log "response.body"
        log response.body
      end

      log "request status : #{response.code}"

      payload = JSON.parse(response.body)

      if interpolated['changes_only'] == 'true'
        if payload.to_s != memory['last_status']
          if "#{memory['last_status']}" == ''
            payload.each do |currency|
              create_event payload: currency
            end
          else
          log "not equal"
            last_status = memory['last_status'].gsub("=>", ": ").gsub(": nil", ": null")
            last_status = JSON.parse(last_status)
            payload.each do |currency|
              found = false
              last_status.each do |currencybis|
                log "currencybis #{currencybis}"
                if currency == currencybis
                    found = true
                end
              end
              if found == false
                  create_event payload: currency
              end
            end
          end
          memory['last_status'] = payload.to_s
        end
      else
        create_event payload: payload
        if payload.to_s != memory['last_status']
          memory['last_status'] = payload.to_s
        end
      end
    end
  end
end
