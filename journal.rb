require 'pp'
require 'date'
require 'csv'
require 'set'
require 'bigdecimal'


class Array
    def cumulative_sum
        sum = 0
        self.map {|x| sum += x}
    end

    def leading_sequence_size(other)
        shortest = [self.size, other.size].min
        i = 0
        # i += 1 while self[i] == other[i] && i <= shortest
        while self[i] == other[i] && i < shortest
            i += 1
        end
        return i
    end
end


def first_of_the_month(d)
    return Date.new(d.year, d.month, 1)
end

def next_month(d)
    return Date.new(d.month != 12 ? d.year : d.year + 1, d.month < 12 ? d.month + 1 : 1, 1)
end

class Journal
    CSV_FIELDS = ["date", "code", "payee", "account", "currency", "amount", "cost", "note"]

    attr_reader :transactions

    def initialize(transactions)
        @transactions = transactions
    end

    def self.from_csv_arr(arr)
        transactions = arr.map {|a| Hash[ Journal::CSV_FIELDS.zip(a) ] }
        transactions.each { |t|
            t['amount'] = BigDecimal(t['amount'])
            d = t['date'].split('/')
            d.map! { |v| v.to_i }
            t['date'] = Date.new(d[0], d[1], d[2])
        }
        transactions.sort_by! { |t| t['date'] }
        Journal.new(transactions)
    end

    def self.from_csv_file(filename)
        Journal.from_csv_arr(CSV::read(filename))
    end

    def self.from_csv(content)
        Journal.from_csv_arr(CSV::parse(content))
    end

    def size
        @transactions.size
    end

    def accounts
        Set.new @transactions.map { |t| t['account'] }
    end

    def where
        Journal.new(@transactions.select { |t| yield(t) })
    end

    def for_account(account)
        self.where { |t| t["account"].start_with?(account) }
    end

    def for_month(year, month)
        self.where { |t| t["date"].year == year && t["date"].month == month }
    end

    def uncleared
        self.where { |t| t["cost"].empty? }
    end

    def balance
        @transactions.inject(0) { |sum, tr| sum + tr['amount'] }
    end

    def monthly_register
        register = @transactions.group_by{ |t| first_of_the_month(t["date"]) }.to_a
        register.sort_by! { |e| e[0] }
        register
    end

    def monthly_subtotals(_monthly_register = monthly_register())
        _monthly_register.map { |m, transactions|
            [m, transactions.sum { |tr| tr['amount'] }]
        }
    end

    def monthly_balances(_monthly_subtotals = monthly_subtotals())
        months = _monthly_subtotals.map { |s| next_month(s[0]) }
        balances = _monthly_subtotals.map { |s| s[1] }.cumulative_sum
        months.zip(balances)
    end

    def summary
        tree = AccountTree.new(accounts())
        tree.fill(@transactions)
        return tree
    end
end

class AccountTree
    include Enumerable

    def initialize(accounts)
        @root = Node.new(:root)
        accounts.sort.each { |a| @root.push(a.split(':')) }
    end

    def each
        @root.iterate { |account| yield account }
    end

    def fill(transactions)
        transactions.each { |tr|
            @root.register tr['account'].split(':'), tr['amount']
        }
    end

    def accumulate
        @root.accumulate
    end

    def print
        each { |a| puts(("\t" * a[:level]) + a[:name] + ': ' + ("%.2f" % a[:amount])) }
    end

    class Node
        attr_accessor :name, :nodes, :amount

        def initialize(name)
            @name = name
            @nodes = []
            @amount = BigDecimal(0)
        end

        def push(a)
            #puts "Processing #{a}"

            parent_node = nil
            leading_sequence_size = 0

            @nodes.each { |node|
                s = a.leading_sequence_size(node.name)

                if s > leading_sequence_size
                    parent_node = node
                    leading_sequence_size = s
                end
            }

            s = leading_sequence_size

            # puts "Common sequence size: #{s}"
            # if s > 0
            #   puts "Common sequence: #{parent_node.name[0, s].join(':')}"
            # end

            if parent_node.nil?
                # puts "No parent node"
                @nodes.push Node.new(a)
            elsif parent_node.name.size() == s
                # puts "Parent found: #{parent_node.name.join(':')}, " +
                #      "does not need to be splitted"
                # puts "Pushing: #{a[s..-1]}"
                parent_node.push(a[s..-1])
            else
                # puts "Parent found: #{parent_node.name.join(':')}, " +
                #      "need to be split in #{parent_node.name[0, s].join(':')} and #{parent_node.name[s..-1].join(':')}"
                parent_right = Node.new(parent_node.name[s..-1])
                parent_right.nodes = parent_node.nodes

                parent_node.name = parent_node.name[0, s]
                parent_node.nodes = [parent_right]

                # puts "Pushing: #{a[s..-1]}"
                parent_node.push(a[s..-1])
            end
        end

        def dump(parent = nil)
            if parent.nil?
                return {name: @name.join(':'), fullname: @name.join(':'), level: 0, amount: @amount}
            else
                name = @name.join(':')
                return {name: name, fullname: parent[:fullname] + ':' + name, level: parent[:level] + 1, amount: @amount}
            end
        end

        def iterate(parent = nil)
            if @name == :root
                @nodes.each { |node|
                    node.iterate(nil) { |a| yield a }
                }
            else
                self_dump = dump(parent)
                yield self_dump
                @nodes.each { |node|
                    node.iterate(self_dump) { |a| yield a }
                }
            end
        end

        def register(account, amount)
            if account.empty?
                @amount += amount
                return
            end

            parent_node = nil
            leading_sequence_size = 0

            @nodes.each { |node|
                s = account.leading_sequence_size(node.name)
                if s > 0
                    parent_node = node
                    leading_sequence_size = s
                    break
                end
            }

            parent_node.register(account[leading_sequence_size..-1], amount)
        end

        def accumulate
            @nodes.each { |n| n.accumulate }

            return if @nodes.empty?

            @amount += @nodes.inject(0) { |sum, node| sum + node.amount }
        end
    end
end
