-- ============================================================
-- MIGRATION: Wer auf die Getränkeliste kommt (je Person an-/abwählbar)
-- Einmalig im SQL Editor ausführen.
-- ============================================================

alter table public.payouts add column if not exists drink_list boolean not null default true;
-- Kein neues RLS nötig: "payouts: nur Admin" (Migration 0006) gilt
-- zeilenbasiert für die ganze Tabelle, also auch für diese Spalte.
