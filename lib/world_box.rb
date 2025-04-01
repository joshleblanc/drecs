module Drecs 
    class WorldBox
        include Enumerable
        
        def initialize(world:, after_add: nil)
            @world = world 
            @members = []
            @after_add = after_add
        end

        def <<(entity)
            entity.world = @world
            @members << entity
            
            if @after_add
                @after_add.call(entity)
            end
        end

        def length 
            @members.length 
        end

        def each(&blk)
            Array.each(@members, &blk)
        end

        def select(&blk)
            Array.select(@members, &blk)
        end

        def [](index)
            @members[index]
        end

        def []=(index, value)
            @members[index] = value
        end
    end
end