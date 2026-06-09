-- adoptions 테이블에 slot_id 컬럼 추가 (디자인권 분양 연결)
ALTER TABLE public.adoptions
  ADD COLUMN IF NOT EXISTS slot_id uuid REFERENCES public.slots(id);
