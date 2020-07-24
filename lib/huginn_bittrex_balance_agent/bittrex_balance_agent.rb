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

      unless options['expected_receive_period_in_days'].present? && options['expected_receive_period_in_days'].to_i > 0
        errors.add(:base, "Please provide 'expected_receive_period_in_days' to indicate how many days can pass before this Agent is considered to be not working")
      end
    end

    def working?
      memory['last_status'].to_i > 0

      return false if recent_error_logs?
      
      if interpolated['expected_receive_period_in_days'].present?
        return false unless last_receive_at && last_receive_at > interpolated['expected_receive_period_in_days'].to_i.days.ago
      end

      true
    end

    def check
      fetch
    end

    private
    
    # Generate a continually-increasing unsigned 51-bit integer nonce from the
    # current Unix Time.
    #
    def generate_nonce
# doesn't work....
#      (Time.now.to_f * 1_000_000).to_i
      `date +%s`.to_i
    end

    def signature(url)
      ::OpenSSL::HMAC.hexdigest 'sha512', interpolated['secret_key'], url
    end

    def fetch
      nonce = generate_nonce
      url = "https://bittrex.com/api/v1.1/account/getbalances?apikey=" + "#{interpolated['apikey']}" + "&nonce=" + "#{nonce}"
      uri = URI.parse(url)
      request = Net::HTTP::Get.new(uri)
      request["Apisign"] = signature(url)
      
      req_options = {
        use_ssl: uri.scheme == "https",
      }
  
      response = Net::HTTP.start(uri.hostname, uri.port, req_options) do |http|
        http.request(request)
      end

      log "request  status : #{response.code}"

      payload = JSON.parse(response.body)

      if interpolated['changes_only'] == 'true'
        if payload['result'].to_s != memory['last_status']
          if "#{memory['last_status']}" == ''
            payload['result'].each do |currency|
              create_event payload: currency
            end
          else
          log "not equal"
            last_status = memory['last_status'].gsub("=>", ": ").gsub(": nil", ": null")
            last_status = JSON.parse(last_status)
            payload['result'].each do |currency|
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
          memory['last_status'] = payload['result'].to_s
        end
      else
        create_event payload: payload['result']
        if payload['result'].to_s != memory['last_status']
          memory['last_status'] = payload.to_s
        end
      end
    end
  end
end
