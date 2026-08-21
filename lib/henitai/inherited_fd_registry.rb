# frozen_string_literal: true

module Henitai
  # Tracks parent-process file handles that a forked child must not keep open.
  #
  # The motivating case is the reports-directory lock. `flock` is held on the
  # open file *description*, which parent and child share after a fork. If a
  # child outlives its parent while holding an inherited copy of that handle,
  # the lock stays held by a process that is no longer running a mutation run,
  # and every later invocation fails with a ConcurrentRunError naming a dead
  # pid. Closing the child's copy immediately after fork means the lock dies
  # with the parent, as intended.
  #
  # Registration is parent-side; #close_all! is the child-side call. The
  # registry deliberately holds IO objects rather than file descriptor numbers:
  # a child that recreated the handle via IO.for_fd would leave the original
  # object alive, and its finalizer could later close a descriptor number the
  # child had since reused for something else.
  module InheritedFdRegistry
    @ios = []
    @mutex = Mutex.new

    class << self
      def register(io)
        @mutex.synchronize { @ios << io }
        io
      end

      def unregister(io)
        @mutex.synchronize { @ios.delete(io) }
        io
      end

      # @return [Array<IO>] copy of the tracked handles
      def registered
        @mutex.synchronize { @ios.dup }
      end

      # Closes every tracked handle. Call this in the child, immediately after
      # Process.fork.
      #
      # This deliberately does NOT take the mutex. `fork` can land while
      # another thread in the parent holds it -- the coverage bootstrap thread
      # and the scheduler's worker threads both run concurrently with spawning
      # -- and only the forking thread survives into the child. Waiting on a
      # mutex whose owner does not exist there would hang the child forever.
      # Reading a stale snapshot is harmless; deadlocking is not.
      def close_all!
        ios = @ios.dup
        @ios = []
        ios.each { |io| close_quietly(io) }
        nil
      end

      private

      # Runs in a just-forked child, where raising would take down the whole
      # mutant run rather than the one handle that failed.
      def close_quietly(io)
        io.close unless io.closed?
      rescue IOError, SystemCallError
        nil
      end
    end
  end
end
