#!/usr/bin/ruby

require 'rubygems'
require 'sinatra'
require 'sinatra/config_file'
require 'thin'
require 'json'
require 'rack/utils'
require 'tilt/haml'
require 'haml/template/options'
require 'digest'
require 'shellwords'
require 'open3'
require 'i18n'
require 'i18n/backend/fallbacks'

require 'action_view'
require 'action_view/helpers'
include ActionView::Helpers::NumberHelper

require_relative 'journal'
require_relative 'cache'

set :logging, false

config_file 'config.yml'

set :server, 'thin'
set :haml, { attr_wrapper: '"' }

I18n::Backend::Simple.send(:include, I18n::Backend::Fallbacks)
# Only load the requested locale and the default one (en)
I18n.load_path += [File.join('locales', "en.yml"), File.join('locales', "#{settings.locale}.yml")]
I18n.backend.load_translations
I18n.default_locale = 'en'

before do
    I18n.locale = settings.locale # Apparently, it needs to be set for each request

    @journal_current_hash = Digest::MD5.file settings.ledger_file

    @stylesheets = ["//maxcdn.bootstrapcdn.com/bootstrap/3.3.4/css/bootstrap.min.css",
                    url("style.css"),
                    url("css/jquery.treegrid.css")]
    @scripts = ["https://ajax.googleapis.com/ajax/libs/jquery/2.1.4/jquery.min.js",
                "//maxcdn.bootstrapcdn.com/bootstrap/3.3.4/js/bootstrap.min.js",
                url("js/jquery.treegrid.min.js"),
                url("js/jquery.treegrid.bootstrap3.js"),
                url("js/highcharts.js")]
end

helpers do
    def journal
        unless Cache.cached(:journal, @journal_current_hash)
            puts "Caching journal"
            cmd = [settings.ledger_cmd, "-f", settings.ledger_file, "--input-date-format", settings.date_format, "csv"].shelljoin
            stdout, stdeerr, status = Open3.capture3(cmd)
            stdout.force_encoding("UTF-8")
            Cache.cache(:journal, Journal::from_csv(stdout), @journal_current_hash)
        end

        return Cache.get(:journal)
    end

    def h(text)
        Rack::Utils.escape_html(text)
    end

    def t(*args)
        I18n.translate(*args)
    end

    def l(*args)
        I18n.l(*args)
    end

    def abbr_month_list
        "[" + t(:abbr_month_names, :scope => :date)[1..-1].map{ |e| "\"#{e}\""}.join(", ") + "]"
    end

    def money(v)
        number_to_currency(v, :unit => settings.currency,
                              :delimiter => settings.thousand_sep,
                              :separator => settings.decimal_sep,
                              :precision => settings.decimals,
                              :format => settings.currency_format)
    end

    def highcharts_serie(history)
        decimal_format = "%.#{settings.decimals}f"
        history.map{ |hist| "[#{hist[0].strftime('%Q')}, #{decimal_format % hist[1]}]" }.join(", ")
    end

    def highcharts_series(balances)
        s = ""
        balances.map { |account, history|
            "{\n" +
            "  name: '#{account}',\n" +
            "  data: [ " + highcharts_serie(history) + " ]" +
            "\n}"
        }.join(",\n")
    end
end

get "/" do
    assets = journal().for_account(settings.assets)
    accounts = assets.accounts().sort

    summary = assets.summary
    summary.accumulate

    balances = [[settings.assets, assets.monthly_balances()]] + accounts.map { |a| [a, assets.for_account(a).monthly_balances() ] }

    haml :index, :layout => :main_layout, locals: {summary: summary, balances: balances, account_title: settings.assets}
end

get "/#{I18n.t 'text.account', locale: settings.locale}/:name" do |account|
    account_journal = journal().for_account(account)

    summary = account_journal.summary
    summary.accumulate

    variations = [ [account, account_journal.uncleared.monthly_subtotals()] ]
    haml :account_details, :layout => :main_layout, locals: {account_title: account, summary: summary, variations: variations}
end
