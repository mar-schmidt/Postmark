import { createFileRoute } from "@tanstack/react-router";
import { SiteNav, SiteFooter } from "@/components/SiteNav";
import shot1 from "@/assets/shot-01.png";
import shot2 from "@/assets/shot-02.png";
import shot3 from "@/assets/shot-03.png";
import shot4 from "@/assets/shot-04.png";

export const Route = createFileRoute("/")({
  component: Index,
  head: () => ({
    meta: [
      { title: "Postmark — Fast, focused Gmail in your menu bar" },
      { name: "description", content: "A clean macOS menu bar app for Gmail. Triage your inbox, read messages, and reply without leaving what you're doing." },
      { property: "og:title", content: "Postmark — Fast, focused Gmail in your menu bar" },
      { property: "og:description", content: "A clean macOS menu bar app for Gmail. Triage, read, and reply without clutter." },
      { property: "og:url", content: "/" },
    ],
    links: [{ rel: "canonical", href: "/" }],
  }),
});

const features = [
  { img: shot1, title: "Your inbox, one click away.", desc: "Postmark lives in your menu bar. Open it instantly without switching apps or losing focus." },
  { img: shot2, title: "Read it. Done. Back to work.", desc: "A thread view designed for fast reading — clean typography, no clutter, no chrome." },
  { img: shot3, title: "Reply without leaving what you're doing.", desc: "Quick reply lets you respond in seconds and get back to whatever you were working on." },
  { img: shot4, title: "Gone in a swipe.", desc: "Archive with a single tap. Triage your inbox in moments, not minutes." },
];

function Index() {
  return (
    <div className="min-h-screen bg-background text-foreground">
      <SiteNav />

      <section className="relative overflow-hidden">
        <div
          className="absolute inset-0 -z-10 opacity-90"
          style={{ background: "var(--gradient-hero)" }}
        />
        <div className="mx-auto max-w-5xl px-6 pt-24 pb-32 text-center text-primary-foreground">
          <span className="inline-block px-3 py-1 rounded-full text-xs font-medium bg-white/15 backdrop-blur-sm border border-white/20 text-slate-50">
            For macOS
          </span>
          <h1 className="mt-6 text-4xl sm:text-5xl md:text-6xl font-bold tracking-tight text-white">
            Gmail, in your<br />menu bar.
          </h1>
          <p className="mt-6 text-lg sm:text-xl text-white/85 max-w-2xl mx-auto">
            Postmark is a clean, fast email app built for people who want to move through Gmail quickly. Read, triage, and reply with less friction.
          </p>
          <div className="mt-10 flex justify-center gap-3">
            <a href="#download" className="inline-flex items-center px-6 py-3 rounded-full bg-white text-background font-medium hover:bg-white/90 transition-colors">
              Download for Mac
            </a>
            <a href="#features" className="inline-flex items-center px-6 py-3 rounded-full bg-white/10 text-white border border-white/30 hover:bg-white/20 transition-colors">
              See how it works
            </a>
          </div>
        </div>
      </section>

      <section id="features" className="mx-auto max-w-6xl px-6 py-24 space-y-32 bg-slate-800">
        {features.map((f, i) => (
          <div key={i} className="grid md:grid-cols-2 gap-12 items-center">
            <div className={i % 2 ? "md:order-2" : ""}>
              <h2 className="text-3xl sm:text-4xl font-bold tracking-tight">{f.title}</h2>
              <p className="mt-4 text-lg text-muted-foreground">{f.desc}</p>
            </div>
            <div className={i % 2 ? "md:order-1" : ""}>
              <img src={f.img} alt={f.title} className="rounded-2xl shadow-xl w-full" loading="lazy" />
            </div>
          </div>
        ))}
      </section>

      <section id="download" className="mx-auto max-w-3xl px-6 py-24 text-center">
        <h2 className="text-4xl font-bold tracking-tight">Spend less time in email.</h2>
        <p className="mt-4 text-lg text-muted-foreground">Available on the Mac App Store.</p>
        <a href="#" className="mt-8 inline-flex items-center px-6 py-3 rounded-full bg-primary text-primary-foreground font-medium hover:opacity-90 transition-opacity">
          Download Postmark
        </a>
      </section>

      <SiteFooter />
    </div>
  );
}
