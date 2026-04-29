/*
 * site.js — front-page logic for mah-stack-starter
 *
 * Three things happen on page load:
 *   1. Read the Supabase config injected into window.SUPABASE_URL /
 *      window.SUPABASE_ANON_KEY by the build (or you, if doing it manually).
 *   2. Try a small read against the `members` table to prove the backend
 *      is reachable; show a status badge in the hero.
 *   3. Wire the magic-link sign-in form to supabase.auth.signInWithOtp.
 *
 * Everything else (your actual site content) replaces the surrounding
 * HTML in index.html. This file is the smallest functional bootstrap.
 */

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const supabaseUrl = window.SUPABASE_URL;
const supabaseAnon = window.SUPABASE_ANON_KEY;

const placeholders = [
  "__SUPABASE_URL__",
  "__SUPABASE_ANON_KEY__",
  "",
  undefined,
];

const status = document.querySelector("#backend-status [data-state]");

if (placeholders.includes(supabaseUrl) || placeholders.includes(supabaseAnon)) {
  status.dataset.state = "error";
  status.textContent =
    "not configured — set SUPABASE_URL + SUPABASE_ANON_KEY in your hosting env vars";
} else {
  const supabase = createClient(supabaseUrl, supabaseAnon);

  // Backend reachability check
  (async () => {
    try {
      const { error } = await supabase
        .from("members")
        .select("id", { count: "exact", head: true });
      if (error && error.code !== "PGRST116") throw error;
      status.dataset.state = "ok";
      status.textContent = "connected ✓";
    } catch (err) {
      status.dataset.state = "error";
      status.textContent = "unreachable: " + err.message;
    }
  })();

  // Magic-link sign-in form
  const form = document.getElementById("signin-form");
  const formStatus = document.getElementById("signin-status");
  if (form) {
    form.addEventListener("submit", async (e) => {
      e.preventDefault();
      const email = e.target.email.value;
      formStatus.hidden = false;
      formStatus.textContent = "Sending…";

      const { error } = await supabase.auth.signInWithOtp({
        email,
        options: { emailRedirectTo: window.location.origin + "/" },
      });

      formStatus.textContent = error
        ? `Couldn't send link: ${error.message}`
        : "Check your inbox for a sign-in link.";
    });
  }

  // Show signed-in state if we already are
  (async () => {
    const {
      data: { user },
    } = await supabase.auth.getUser();
    if (!user) return;
    const authStatus = document.getElementById("auth-status");
    if (!authStatus) return;
    authStatus.hidden = false;
    authStatus.textContent = `Signed in as ${user.email}.`;
  })();
}
