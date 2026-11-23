# frozen_string_literal: true

module Henitai
  class MutantHistoryStore
    # Connection, schema and transaction handling for {MutantHistoryStore}.
    # Mixed in; relies on its +path+.
    module Database
      private

      # One transaction per write, committed or rolled back as a whole: signals
      # wait until it ends, and any exception -- not only a StandardError, which
      # is all sqlite3's block form rolls back for -- undoes it.
      def write
        FileUtils.mkdir_p(File.dirname(path))
        SignalDeferral.call do
          with_database do |db|
            ensure_schema(db)
            atomically(db) { yield db }
          end
        end
      end

      def atomically(db)
        db.transaction
        yield
        db.commit
      rescue Exception # rubocop:disable Lint/RescueException -- an Interrupt must roll back too
        db.rollback if db.transaction_active?
        raise
      end

      def with_database
        db = SQLite3::Database.new(path)
        db.results_as_hash = true
        yield db
      ensure
        db&.close
      end

      def ensure_schema(db)
        db.execute_batch(Sql::RUNS_TABLE)
        db.execute_batch(Sql::MUTANTS_TABLE)
        migrate_subject_scans_table(db)
        db.execute_batch(SubjectScans::SUBJECT_SCANS_TABLE)
        migrate_mutants_table(db)
      end

      # Additive, idempotent in-place migration: databases created before the
      # verdict-cache columns existed gain them on first contact, with existing
      # rows left intact (NULL hashes — valid but never reusable).
      def migrate_mutants_table(db)
        existing = db.execute("PRAGMA table_info(mutants)").map { |row| row["name"] }
        Sql::MIGRATION_COLUMNS.each do |column, type|
          next if existing.include?(column)

          db.execute("ALTER TABLE mutants ADD COLUMN #{column} #{type}")
        end
      end
    end
  end
end
