// Login / Signup page logic.
// On load: if a session already exists, jump straight to home.html.
// On submit: sign in or sign up with email/password, then redirect.

document.addEventListener('alpine:init', () => {
  Alpine.data('loginPage', () => ({
    configMissing: !!window.__configMissing || !window.SUPABASE_URL || !window.SUPABASE_KEY,
    supabase: null,

    mode: 'signin',      // 'signin' | 'signup'
    email: '',
    password: '',
    loading: false,
    error: '',

    toasts: [],

    async init() {
      if (this.configMissing) return;
      try {
        this.supabase = window.supabase.createClient(window.SUPABASE_URL, window.SUPABASE_KEY);
      } catch (err) {
        console.error('Supabase init failed:', err);
        this.configMissing = true;
        return;
      }
      // If already logged in, skip the form
      const { data: { session } } = await this.supabase.auth.getSession();
      if (session) window.location.replace('home.html');
    },

    toggleMode() {
      this.mode = this.mode === 'signin' ? 'signup' : 'signin';
      this.error = '';
    },

    notify(message, type = 'info') {
      const id = Date.now() + Math.random();
      this.toasts.push({ id, message, type });
      setTimeout(() => {
        this.toasts = this.toasts.filter(t => t.id !== id);
      }, 3500);
    },

    async submit() {
      this.error = '';
      this.loading = true;
      try {
        if (this.mode === 'signin') {
          const { data, error } = await this.supabase.auth.signInWithPassword({
            email: this.email.trim(),
            password: this.password,
          });
          if (error) throw error;
          if (data.session) {
            window.location.replace('home.html');
          } else {
            this.error = 'Sign-in returned no session — try again.';
          }
        } else {
          const { data, error } = await this.supabase.auth.signUp({
            email: this.email.trim(),
            password: this.password,
          });
          if (error) throw error;
          if (data.session) {
            // Auto-confirmation: jump to app
            window.location.replace('home.html');
          } else {
            // Email confirmation required
            this.notify(
              'Account created. Check your inbox to confirm your email, then sign in.',
              'positive'
            );
            this.mode = 'signin';
            this.password = '';
          }
        }
      } catch (err) {
        console.error('Auth error:', err);
        this.error = err.message || String(err);
      } finally {
        this.loading = false;
      }
    },
  }));
});
