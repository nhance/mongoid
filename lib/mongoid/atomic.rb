# encoding: utf-8
require "mongoid/atomic/modifiers"
require "mongoid/atomic/paths"

module Mongoid #:nodoc:

  # This module contains the logic for supporting atomic operations against the
  # database.
  module Atomic
    extend ActiveSupport::Concern

    included do

      # When MongoDB finally fully implements the positional operator, we can
      # get rid of all indexing related code in Mongoid.
      attr_accessor :_index
    end

    # Get all the atomic updates that need to happen for the current
    # +Document+. This includes all changes that need to happen in the
    # entire hierarchy that exists below where the save call was made.
    #
    # @note MongoDB does not allow "conflicting modifications" to be
    #   performed in a single operation. Conflicting modifications are
    #   detected by the 'haveConflictingMod' function in MongoDB.
    #   Examination of the code suggests that two modifications (a $set
    #   and a $pushAll, for example) conflict if:
    #     (1) the key paths being modified are equal.
    #     (2) one key path is a prefix of the other.
    #   So a $set of 'addresses.0.street' will conflict with a $pushAll
    #   to 'addresses', and we will need to split our update into two
    #   pieces. We do not, however, attempt to match MongoDB's logic
    #   exactly. Instead, we assume that two updates conflict if the
    #   first component of the two key paths matches.
    #
    # @example Get the updates that need to occur.
    #   person.atomic_updates(children)
    #
    # @return [ Hash ] The updates and their modifiers.
    #
    # @since 2.1.0
    def atomic_updates
      Modifiers.new.tap do |mods|
        mods.set(atomic_sets)
        _children.each do |child|
          mods.set(child.atomic_sets)
          mods.push(child.atomic_pushes)
        end
      end
    end
    alias :_updates :atomic_updates

    # Get the removal modifier for the document. Will be nil on root
    # documents, $unset on embeds_one, $set on embeds_many.
    #
    # @example Get the removal operator.
    #   name.remover
    #
    # @return [ String ] The pull or unset operation.
    def atomic_delete_modifier
      atomic_paths.delete_modifier
    end

    # Get the insertion modifier for the document. Will be nil on root
    # documents, $set on embeds_one, $push on embeds_many.
    #
    # @example Get the insert operation.
    #   name.inserter
    #
    # @return [ String ] The pull or set operator.
    def atomic_insert_modifier
      atomic_paths.insert_modifier
    end

    # Return the path to this +Document+ in JSON notation, used for atomic
    # updates via $set in MongoDB.
    #
    # @example Get the path to this document.
    #   address.path
    #
    # @return [ String ] The path to the document in the database.
    def atomic_path
      atomic_paths.path
    end

    # Returns the positional operator of this document for modification.
    #
    # @example Get the positional operator.
    #   address.position
    #
    # @return [ String ] The positional operator with indexes.
    def atomic_position
      atomic_paths.position
    end

    # Get all the push attributes that need to occur.
    #
    # @example Get the pushes.
    #   person._pushes
    #
    # @return [ Hash ] The $pushAll operations.
    #
    # @since 2.1.0
    def atomic_pushes
      pushable? ? { atomic_path => as_document } : {}
    end

    # Return the selector for this document to be matched exactly for use
    # with MongoDB's $ operator.
    #
    # @example Get the selector.
    #   address.selector
    #
    # @return [ String ] The exact selector for this document.
    def atomic_selector
      atomic_paths.selector
    end

    # Get all the attributes that need to be set.
    #
    # @example Get the sets.
    #   person._sets
    #
    # @return [ Hash ] The $set operations.
    #
    # @since 2.1.0
    def atomic_sets
      updateable? ? setters : settable? ? { atomic_path => as_document } : {}
    end

    private

    # Get the atomic paths utility for this document.
    #
    # @example Get the atomic paths.
    #   document.atomic_paths
    #
    # @return [ Object ] The associated path.
    #
    # @since 2.1.0
    def atomic_paths
      @atomic_paths ||= metadata ? metadata.path(self) : Atomic::Paths::Root.new(self)
    end
  end
end
