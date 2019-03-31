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

    @stylesheets = ["//maxcdn.bootstrapcdn.com/bootstrap/3.3.7/css/bootstrap.min.css",
                    url("style.css"),
                    url("css/jquery.treegrid.css")]
    @scripts = ["https://ajax.googleapis.com/ajax/libs/jquery/3.3.1/jquery.min.js",
                "//maxcdn.bootstrapcdn.com/bootstrap/3.3.7/js/bootstrap.min.js",
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

    def amount_signed(v, account)
        account.start_with?(settings.assets) ? v : -v
    end

    def money_signed(v, account)
        money(amount_signed(v, account))
    end

    def highcharts_serie(history, negate = false)
        decimal_format = "%.#{settings.decimals}f"
        factor = negate ? -1 : 1
        history.map{ |hist|
            "[#{hist[0].strftime('%Q')}, #{decimal_format % (factor * hist[1])}]"
        }.join(", ")
    end

    def highcharts_series(balances, negate = false)
        s = ""
        balances.map { |account, history|
            "{\n" +
            "  name: '#{account}',\n" +
            "  data: [ " + highcharts_serie(history, negate) + " ]" +
            "\n}"
        }.join(",\n")
    end
end

get "/" do
    assets = journal().for_account(settings.assets)
    accounts = assets.accounts().sort

    summary = assets.summary
    summary.accumulate

    monthly_register = assets.monthly_register
    monthly_register.each { |monthly| monthly[1].sort_by! { |e| e['date'] } }

    monthly_subtotals = assets.monthly_subtotals(monthly_register)

    balances = [[settings.assets, assets.monthly_balances(monthly_subtotals)]] + accounts.map { |a| [a, assets.for_account(a).monthly_balances() ] }
    variations = [ [settings.assets, monthly_subtotals] ]

    haml :index, :layout => :main_layout, locals: {account: settings.assets,
                                                   summary: summary,
                                                   balances: balances,
                                                   variations: variations,
                                                   account_title: settings.assets,
                                                   monthly_register: monthly_register.last(2)}
end

get "/account/:account" do |account|
    account_journal = journal().for_account(account)

    summary = account_journal.summary
    summary.accumulate

    monthly_register = account_journal.monthly_register
    monthly_register.each { |monthly| monthly[1].sort_by! { |e| e['date'] } }

    variations = [ [account, account_journal.monthly_subtotals(monthly_register)] ]
    haml :account_details, :layout => :main_layout, locals: {account: account,
                                                             summary: summary,
                                                             variations: variations,
                                                             monthly_register: monthly_register.last(2)}
end

get "/transactions/:account" do |account|
    account_journal = journal().for_account(account)

    summary = account_journal.summary
    summary.accumulate

    monthly_register = account_journal.monthly_register
    monthly_register.each { |monthly| monthly[1].sort_by! { |e| e['date'] } }

    haml :transactions, :layout => :main_layout, locals: {account: account,
                                                          summary: summary,
                                                          monthly_register: monthly_register}
end
