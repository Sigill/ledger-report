class Cache
	@@data = Hash.new

	def self::cached(key, hash)
		return @@data.has_key?(key) && @@data[key].hash == hash
	end

	def self::cache(key, value, hash)
		@@data[key] = CacheItem.new(value, hash)
	end

	def self::get(key)
		return @@data[key].value
	end

	class CacheItem
		attr_reader :value, :hash
		def initialize(value, hash)
			@value = value
			@hash = hash
		end
	end
end