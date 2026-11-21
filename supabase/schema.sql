-- Despedida de Sanae · base de datos (Supabase)
-- Pegar entero en Supabase > SQL Editor > New query > Run.
-- Se puede volver a ejecutar: borra y recrea las tablas (¡reinicia todo el progreso y los textos!).

drop function if exists public.app_state();
drop function if exists public.app_try(text, text);
drop function if exists public.norm_word(text);
drop function if exists public.day_open(boolean, timestamptz);
drop table if exists public.words;
drop table if exists public.days;

create table public.days (
  id text primary key,
  pos int not null,
  title text not null,
  kicker text not null,
  intro text not null default '',
  opens_at timestamptz,                         -- a partir de cuándo se ve el día (null = siempre)
  force_open boolean not null default false,    -- el admin lo abre ya, sin esperar a la fecha
  seq boolean not null default true,            -- true: palabras en orden; false: las desbloquea el admin una a una
  plan_title text not null default '',          -- título del planning que desbloquea este día
  plan_body text not null default '',           -- una línea por parada: "hora | título | descripción" (hora vacía = "Después")
  plan_force boolean not null default false     -- el admin enseña el planning aunque no haya acertado todo
);

create table public.words (
  id text primary key,
  day text not null references public.days(id) on delete cascade,
  pos int not null,
  label text not null,                          -- cómo se enseña la palabra al acertar
  riddle text not null,
  accept text not null,                         -- respuestas válidas separadas por |
  clue text not null,                           -- pista que desbloquea
  unlocked boolean not null default false,      -- solo para días con seq=false
  fails int not null default 0,
  solved boolean not null default false
);

alter table public.days enable row level security;
alter table public.words enable row level security;
revoke all on public.days, public.words from anon;
grant all on public.days, public.words to authenticated;
create policy admin_days on public.days for all to authenticated using (true) with check (true);
create policy admin_words on public.words for all to authenticated using (true) with check (true);

-- ¿Se ve ya este día en la web?
create function public.day_open(force boolean, at timestamptz) returns boolean
language sql stable as $$
  select force or at is null or now() >= at
$$;

-- Normaliza como la web: minúsculas, sin tildes, solo letras, sin artículo inicial, sin espacios.
create function public.norm_word(s text) returns text
language plpgsql immutable as $$
declare
  t text;
  parts text[];
begin
  t := lower(coalesce(s, ''));
  t := translate(t, 'áàâäéèêëíìîïóòôöúùûüñç', 'aaaaeeeeiiiioooouuuunc');
  t := regexp_replace(t, '[^a-z ]', ' ', 'g');
  parts := regexp_split_to_array(btrim(t), '\s+');
  if array_length(parts, 1) > 1 and parts[1] = any (array['el','la','los','las','un','una']) then
    parts := parts[2:array_length(parts, 1)];
  end if;
  return array_to_string(parts, '');
end $$;

-- Lo que ve Sanae. Las respuestas y lo bloqueado nunca salen de aquí.
create function public.app_state() returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  d record;
  w record;
  words jsonb;
  ws jsonb;
  st text;
  prev_done boolean;
  all_solved boolean;
  out jsonb := '[]'::jsonb;
  is_open boolean;
begin
  for d in select * from public.days order by pos loop
    is_open := public.day_open(d.force_open, d.opens_at);
    words := '[]'::jsonb;
    prev_done := true;
    all_solved := true;
    for w in select * from public.words where day = d.id order by pos loop
      if w.solved then
        st := 'solved';
      elsif w.fails >= 3 then
        st := 'blown';
      elsif d.seq then
        st := case when prev_done then 'active' else 'locked' end;
      else
        st := case when w.unlocked then 'active' else 'locked' end;
      end if;
      if st <> 'solved' then all_solved := false; end if;
      prev_done := prev_done and st in ('solved', 'blown');
      ws := jsonb_build_object('id', w.id, 'pos', w.pos, 'status', st, 'fails', w.fails);
      if st in ('active', 'blown') then ws := ws || jsonb_build_object('riddle', w.riddle); end if;
      if st = 'solved' then ws := ws || jsonb_build_object('label', w.label, 'clue', w.clue); end if;
      words := words || ws;
    end loop;
    out := out || jsonb_build_array(jsonb_build_object(
      'id', d.id, 'title', d.title, 'kicker', d.kicker, 'open', is_open,
      'intro', case when is_open then d.intro else '' end,
      'words', case when is_open then words else '[]'::jsonb end,
      'finished', is_open and not exists (select 1 from jsonb_array_elements(words) e where e->>'status' in ('active', 'locked')) and jsonb_array_length(words) > 0,
      'all_solved', is_open and all_solved and jsonb_array_length(words) > 0,
      'plan_title', case when is_open and ((all_solved and jsonb_array_length(words) > 0) or d.plan_force) then d.plan_title else null end,
      'plan_body', case when is_open and ((all_solved and jsonb_array_length(words) > 0) or d.plan_force) then d.plan_body else null end
    ));
  end loop;
  return jsonb_build_object('days', out);
end $$;

-- Un intento de Sanae. Devuelve {ok, fails}; el estado completo se pide después con app_state().
create function public.app_try(word_id text, guess text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  w public.words;
  d public.days;
  g text := public.norm_word(guess);
  active_id text;
  hit boolean;
begin
  select * into w from public.words where id = word_id for update;
  if not found then return jsonb_build_object('ok', false, 'error', 'no_word'); end if;
  select * into d from public.days where id = w.day;
  if not public.day_open(d.force_open, d.opens_at) then return jsonb_build_object('ok', false, 'error', 'closed'); end if;
  if w.solved or w.fails >= 3 then return jsonb_build_object('ok', false, 'error', 'done', 'fails', w.fails); end if;
  if d.seq then
    select x.id into active_id from public.words x
      where x.day = d.id and not x.solved and x.fails < 3 order by x.pos limit 1;
    if active_id is distinct from w.id then return jsonb_build_object('ok', false, 'error', 'locked'); end if;
  elsif not w.unlocked then
    return jsonb_build_object('ok', false, 'error', 'locked');
  end if;
  if g = '' then return jsonb_build_object('ok', false, 'error', 'empty', 'fails', w.fails); end if;
  select exists (select 1 from unnest(string_to_array(w.accept, '|')) a where public.norm_word(a) = g) into hit;
  if hit then
    update public.words set solved = true where id = w.id;
    return jsonb_build_object('ok', true, 'fails', w.fails);
  end if;
  update public.words set fails = least(3, fails + 1) where id = w.id;
  return jsonb_build_object('ok', false, 'fails', least(3, w.fails + 1));
end $$;

revoke all on function public.app_state(), public.app_try(text, text) from public;
grant execute on function public.app_state(), public.app_try(text, text) to anon, authenticated;

-- ============================ CONTENIDO INICIAL ============================

insert into public.days (id, pos, title, kicker, intro, opens_at, force_open, seq, plan_title, plan_body, plan_force) values
('viernes', 1, 'Viernes', 'Misión 1',
 'Cada día de tu despedida desbloquea una serie de pruebas. La de hoy: tres acertijos, tres palabras y tres pistas de lo que te espera mañana.',
 null, false, true,
 'Planning del sábado',
 '10:00 | Café y desayuno ligero | Para empezar el día con energía.
 | Paseíto por la ciudad | Sin prisa, a ritmo relajado.
13:00 | Brunch | Ven con hambre.
 | Revelación de la misión del día | Al terminar el brunch descubrirás qué te toca hoy.
 | Tus rincones favoritos | Tú nos enseñas los lugares de la ciudad que más te gustan.
17:00 | Mercadillo y merendola | Mercadillo navideño, con merienda incluida. Abrígate bien.
 | A cambiarse | Un rato para coger fuerzas y arreglarnos.
20:30 | Cena en un restaurante | Todas monas.
 | Noche de reggaeton | Discoteca y música de reggaeton. Ve preparando los pies.',
 false),
('sabado', 2, 'Sábado', 'Misión 2',
 'Cada prueba que consigas nos la cuentas y desbloqueamos una palabra. Cada palabra acertada te da una pista del plan de mañana.',
 '2026-11-28 00:00:00+01', false, false,
 'Planning del domingo', '', false);

insert into public.words (id, day, pos, label, riddle, accept, clue, unlocked) values
('brunch', 'viernes', 1, 'Brunch',
 'Nací de dos comidas que casi no se hablan. Llego tarde para la primera y pronto para la segunda, y quien me pide nunca tiene prisa.',
 'brunch|bruch', 'Habrá brunch. Ven con hambre.', false),
('mercadillo', 'viernes', 2, 'Mercadillo',
 'Soy un pueblo sin vecinos que desaparece sin dejar rastro. Mis casitas no tienen cama ni cocina, pero huelen a Navidad, a canela y a vino caliente. Quien me visita siempre se va con algo que no necesitaba.',
 'mercadillo|mercadillos|mercado|mercados|mercadito|mercado de navidad|mercado navideño|mercadillo de navidad|mercadillo navideño|mercadillo navidad|mercado navidad|christkindlmarkt|christkindlesmarkt|weihnachtsmarkt',
 'Iremos a un mercadillo de Navidad. Abrígate bien.', false),
('reggaeton', 'viernes', 3, 'Reggaeton',
 'Nací en una isla del Caribe, pero me hicieron famoso en discotecas de medio mundo. Mi latido es un «bum, ca, bum, ca» que no se cansa de repetirse, y suena más fuerte cuanto más tarde se hace. No soy un baile: soy lo que suena mientras otros lo bailan, pegados y hasta abajo.',
 'reggaeton|regueton|reggaetton|reguetton|reggeton|regeton', 'Habrá noche de reggaeton. Ve preparando los pies.', false),
('tren', 'sabado', 1, 'Tren',
 'Sigo dos líneas que nunca se tocan y arrastro a mucha gente sin cansarme. Aquí presumo de puntual… y no siempre me creen.',
 'tren|trenes', 'Mañana viajamos en tren.', false),
('tegernsee', 'sabado', 2, 'Tegernsee',
 'Soy pueblo y valle a la vez, al sur de Múnich, a los pies de las montañas. Mi nombre acaba en una palabra que en inglés significa «ver», pero en alemán quiere decir otra cosa.',
 'tegernsee|tegernse|tegern', 'Mañana vamos a Tegernsee.', false),
('lago', 'sabado', 3, 'Lago',
 'Tengo orillas y no soy río; tengo barcos y no soy mar. Las montañas se miran en mí como en un espejo y, cuando estoy quieta, el cielo se ve dos veces.',
 'lago|lagos', 'Mañana hay un lago.', false);
