require 'uri'
require 'net/http'

# Class for translating items using Libre Translate API
class LibreTranslate < NuixTranslator
  NAME = 'Libre Translate'.freeze

  def self.name
    NAME
  end

  
  LANGUAGES = { 
    'auto' => 'Auto',
    'en' => 'English',
    'sq' => 'Albanian',
    'ar' => 'Arabic',
    'az' => 'Azerbaijani',
    'eu' => 'Basque',
    'bg' => 'Bulgarian',
    'bn' => 'Bengali',
    'ca' => 'Catalan',
    'zh' => 'Chinese',
    'zt' => 'Chinese (traditional)',
    'cs' => 'Czech',
    'da' => 'Danish',
    'nl' => 'Dutch',
    'eo' => 'Esperanto',
    'et' => 'Estonian',
    'fi' => 'Finnish',
    'fr' => 'French',
    'gl' => 'Galician',
    'de' => 'German',
    'el' => 'Greek',
    'he' => 'Hebrew',
    'hi' => 'Hindi',
    'hu' => 'Hungarian',
    'id' => 'Indonesian',
    'ga' => 'Irish',
    'it' => 'Italian',
    'ja' => 'Japanese',
    'ko' => 'Korean',
    'lv' => 'Latvian',
    'lt' => 'Lithuanian',
    'ms' => 'Malay',    
    'nb' => 'Norwegian',
    'fa' => 'Persian',
    'pl' => 'Polish',
    'pt' => 'Portuguese',
    'ro' => 'Romanian',
    'ru' => 'Russian',
    'sk' => 'Slovak',
    'sl' => 'Slovenian',
    'es' => 'Spanish',
    'sv' => 'Swedish',
    'tl' => 'Tagalog',
    'th' => 'Thai',
    'tr' => 'Turkish',
    'uk' => 'Ukrainian',
    'ur' => 'Urdu',
  }.freeze

  # Creates a new NuixTranslator using Libre Translate API.
  def initialize
    super(NAME, LANGUAGES)
	@input.setSize(500,400)
    @main_tab.appendTextField('api_url', 'API URL', '')
    @main_tab.appendTextField('char_limit', 'Character Limit', '10000') ## Field for character limit
    @main_tab.appendComboBox('limit_behavior', 'Limit Behavior', ['Ignore', 'Skip', 'Truncate']) ## Menu for character limit
    add_translation_options
    add_translation
    add_translation_tagging
    @input.validateBeforeClosing { |v| validate_input(v) }
  end

  # Adds source language option to main tab of dialog.
  def add_translation_from
    
  end

  def add_translation_tagging
    @main_tab.appendCheckBox('tag_items_success', 'Tag items which are successfully translated?', false)
    @main_tab.appendCheckBox('tag_items_failure', 'Tag items which couldn\'t be translated?', false)
  end

  def add_translation_options
    @main_tab.appendTextField('http_timeout', 'Timeout (sec.)', 30.to_s)
    @main_tab.appendComboBox('translation_language_from', 'Source Language', @langs.values)
  end

  # Runs Translator on the items.
  #
  # @param items [Set<Item>]
  def run(items)
    return nil if super(items).nil?

    @uri = URI.parse(@settings['api_url'])
    @headers = { 'Content-Type' => 'application/json' }
    progress_dialog
  end

  private

  # Translates text using Libre Translate API.
  #
  # @param text [String] original text
  # @return [String, nil] translated text, or nil if there was an error
  def libre_translate(text)
    http = Net::HTTP.new(@uri.host, @uri.port)
    http.use_ssl = true if @uri.instance_of? URI::HTTPS
    http.read_timeout = @settings['http_timeout'].to_i
    begin
      req = Net::HTTP::Post.new(@uri.request_uri, @headers)
      req.body = {  'q' => text,
                    'source' =>  @langs.key(@settings['translation_language_from']),
                    'target' =>  @langs.key(@settings['translation_language'])
        }.to_json
      response = http.request(req)
      puts response.code
      return response_body(response)
    rescue StandardError => ex
      puts "ERROR: #{ex.message}"
    end
  end

  # Progress dialog loop for processing items.
  def progress_dialog
    ProgressDialog.forBlock do |pd|
      super(pd, 'Translating')
      $current_case.with_write_access do
        @items.each_with_index do |item, index|
          break if advance(index, "Item GUID: #{item.getGuid}").nil?

          translate(item)
        end
      end
      pd.setCompleted
    end
  end

  # Handles response from Net::HTTPSuccess
  #
  # @param response [Net::HTTPResponse] from Libre Translate API
  # @return [String, nil] translated text, or nil if an error occured
  def response_body(response)
    case response
    when Net::HTTPSuccess
      puts response.body
      return JSON.parse(response.body)['translatedText']
    when Net::HTTPServerError
      msg = 'try again later?'
    end
    @progress.logMessage("ERROR: #{response.message}")
    @progress.logMessage(msg) unless msg.nil?
  end

  # Translates item using Libre Translate API.
  #
  # @param item [Item] a Nuix item
  def translate(item)
    @progress.setMainStatusAndLogIt('Translating')
## Timeout für Text abholen mit entsprechender Nachricht und Tagging  
  begin
		text = Timeout::timeout(@settings['http_timeout'].to_i) do
			get_original_text(item)
		end
  rescue Timeout::Error
		@progress.logMessage("Getting original Text took too long")
		item.addTag("Translations|failuregettingtext")
		return nil
  end
  
  return nil if text.empty?

  char_limit = @settings['char_limit'].to_i ##provides the character limit from the input and converts it to integer
  limit_behavior = @settings['limit_behavior'] ##provides the limit behavior from the input

##removes all tags, adds the right ones
##returns nil if too long and skip is selected, truncates text to limit if too long and truncate is selected, else translates
  item.removeTag("Translations|failure")
  item.removeTag("Translations|success")
  item.removeTag("Translations|skipped")
  item.removeTag("Translations|truncated")
  item.removeTag("Translations|failuregettingtext")
  t_l = text.length.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1.').reverse
  c_l = char_limit.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1.').reverse
  if text.length > char_limit
    case limit_behavior
    when 'Skip'
      item.addTag("Translations|skipped")
      @progress.logMessage("Text length " + t_l + " > Limit " + c_l + " -> Skipped")
      return nil
    when 'Truncate'
      text = text[0..char_limit]
      item.addTag("Translations|truncated")
      @progress.logMessage("Text length " + t_l + " > Limit " + c_l + " -> Truncated")
    end
  end

  translated = libre_translate(text)
  if translated.nil?
    item.addTag("Translations|failure") if @settings['tag_items_failure']
    @progress.logMessage("No response received! Please try again later")
    return nil 
  end

  item.addTag("Translations|success")

  super(item, translated) unless translated.nil? || translated.empty?
end



  # Validation function for input.
  #  Checks for API URL.
  #
  # @param values [Hash] input values
  # @return [true, false] if in validate state
  def validate_input(values)
    return true unless values['api_url'].strip.empty?

    CommonDialogs.showWarning("Please provide a #{NAME} API URL.")
    false
  end
end
