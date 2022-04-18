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
require 'moving_average'

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
            stdout, stderr, status = Open3.capture3(settings.ledger_cmd, "-f", settings.ledger_file, "--input-date-format", settings.date_format, "csv")
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

    def postprocess_series(history, negate, avg_type, avg_tail)
        history = history.map { |e| [e[0], -e[1]] } if negate

        return history if avg_tail == 1

        values = history.map { |e| e[1] }
        return history.each_with_index.map { |kv, i|
            tail = i < avg_tail ? i+1 : avg_tail
            [
                kv[0],
                case avg_type
                when :sma
                    values.sma(i, tail)
                when :ema
                    values.ema(i, tail)
                when :wma
                    values.wma(i, tail)
                end
            ]
        }
    end

    def highcharts_serie(history, negate, avg_type, avg_tail)
        history = postprocess_series(history, negate, avg_type, avg_tail)
        decimal_format = "%.#{settings.decimals}f"
        history.map{ |hist|
            "[#{hist[0].strftime('%Q')}, #{decimal_format % hist[1]}]"
        }.join(", ")
    end

    def highcharts_series(balances, negate: false, avg_type: :sma, avg_tail: 1, chart_type: 'line')
        s = ""
        balances.map { |account, history|
            "{\n" +
            "  name: '#{account}',\n" +
            "  data: [ " + highcharts_serie(history, negate, avg_type, avg_tail) + " ],\n" +
            "  type: '#{chart_type}'\n" +
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
    variations = [ ['Total', monthly_subtotals] ]

    expenses = [[
        settings.expenses,
        assets.monthly_subtotals(journal().for_account(settings.expenses).monthly_register())
    ]]
    incomes = [[
        settings.incomes,
        assets.monthly_subtotals(journal().for_account(settings.incomes).monthly_register())
    ]]

    haml :index, :layout => :main_layout, locals: {account: settings.assets,
                                                   summary: summary,
                                                   balances: balances,
                                                   variations: variations,
                                                   expenses: expenses,
                                                   incomes: incomes,
                                                   account_title: settings.assets,
                                                   monthly_register: monthly_register.last(2)}
end

get "/account/:account" do |account|
    account_journal = journal().for_account(account)

    summary = account_journal.summary
    summary.accumulate

    monthly_register = account_journal.monthly_register()

    variations = [ [account, account_journal.monthly_subtotals(Journal.make_dense_register(monthly_register))] ]
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

    haml :transactions, :layout => :main_layout, locals: {account: account,
                                                          summary: summary,
                                                          monthly_register: monthly_register}
end
