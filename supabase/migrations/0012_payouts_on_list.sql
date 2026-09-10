-- ============================================================
-- MIGRATION: Auszahlungsliste per Opt-in (Admin wählt Personen einzeln aus)
-- Einmalig im SQL Editor ausführen.
-- ============================================================

-- Standard ist NICHT angehakt: der Admin markiert aktiv, wer auf die
-- Auszahlungsliste kommt, statt dass automatisch alle Personen drauf
-- landen. Gleiches Spalten-Muster wie drink_list (Migration 0007).
alter table public.payouts add column if not exists on_list boolean not null default false;
-- Kein neues RLS nötig: "payouts: nur Admin" (Migration 0006) gilt
-- zeilenbasiert für die ganze Tabelle, also auch für diese Spalte.
