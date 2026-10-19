import { Navbar } from "../components/Navbar";
import { Footer } from "../components/Footer";

export const PrivacyPolicy = () => {
    return (
        <div className="min-h-screen bg-background text-foreground flex flex-col">
            <Navbar />
            <main className="flex-1 max-w-3xl mx-auto px-6 py-20">
                <h1 className="text-4xl font-bold mb-2">Privacy Policy</h1>
                <p className="text-muted-foreground mb-10">
                    Last updated: October 19, 2026
                </p>

                <div className="space-y-8 text-muted-foreground leading-relaxed">
                    <section>
                        <h2 className="text-xl font-semibold text-foreground mb-3">
                            Overview
                        </h2>
                        <p>
                            Chowser is a macOS utility that intercepts browser
                            links and routes them to your configured browsers.
                            Your privacy is important to us. This policy explains
                            what data Chowser handles and how.
                        </p>
                    </section>

                    <section>
                        <h2 className="text-xl font-semibold text-foreground mb-3">
                            Data Collection
                        </h2>
                        <p>
                            <strong className="text-foreground">
                                Chowser does not collect or transmit any
                                personal data.
                            </strong>{" "}
                            All information stays on your Mac.
                        </p>
                    </section>

                    <section>
                        <h2 className="text-xl font-semibold text-foreground mb-3">
                            Data Stored Locally
                        </h2>
                        <p className="mb-3">
                            Chowser stores the following data locally on your
                            device using macOS UserDefaults:
                        </p>
                        <ul className="list-disc list-inside space-y-2 ml-2">
                            <li>
                                Your browser configurations (which browsers to
                                show, display names, profiles)
                            </li>
                            <li>
                                Routing rules you create (domain patterns,
                                browser assignments)
                            </li>
                            <li>
                                Domain click frequency counts (used for
                                picker hints and suggesting routing rules)
                            </li>
                            <li>
                                Link history: for each link Chowser handles,
                                the time, the app that opened it, the link
                                itself, and whether it opened in a browser,
                                opened in a native app, or was dismissed.
                                Private-mode opens are never recorded.
                            </li>
                            <li>
                                App preferences (window position, update
                                settings)
                            </li>
                        </ul>
                        <p className="mt-3">
                            This data never leaves your device and is not
                            accessible to us or any third party.
                        </p>
                        <p className="mt-3">
                            Link history is saved as a file in
                            ~/Library/Application Support/Chowser/ (inside the
                            app container in the App Store version) that only
                            your user account can read. It keeps at most 500
                            links for 30 days and is not included in exports.
                            In Settings → Privacy, set the activity level to
                            Stats only to keep just the website name, or to Off
                            to record nothing and delete the history and domain
                            click counts. Clear History in Settings → Activity
                            deletes the history at any time.
                        </p>
                    </section>

                    <section>
                        <h2 className="text-xl font-semibold text-foreground mb-3">
                            Network Access
                        </h2>
                        <p>
                            Chowser makes network requests only to check for app
                            updates (the App Store version through the App Store,
                            the direct download through GitHub), to download its
                            signed rewrite and native-app catalogs from
                            chowser.sreerams.in, and, only if you turn on online
                            lookups in Settings → Privacy, to expand short links
                            and fetch link previews. Your link history, settings,
                            and usage stats are never sent.
                        </p>
                    </section>

                    <section>
                        <h2 className="text-xl font-semibold text-foreground mb-3">
                            Third-Party Services
                        </h2>
                        <p>Chowser does not integrate with any third-party analytics, tracking, or advertising services.</p>
                    </section>

                    <section>
                        <h2 className="text-xl font-semibold text-foreground mb-3">
                            Children's Privacy
                        </h2>
                        <p>
                            Chowser does not collect any data from anyone,
                            including children under 13.
                        </p>
                    </section>

                    <section>
                        <h2 className="text-xl font-semibold text-foreground mb-3">
                            Changes to This Policy
                        </h2>
                        <p>
                            We may update this privacy policy from time to time.
                            Changes will be posted on this page with an updated
                            date.
                        </p>
                    </section>

                    <section>
                        <h2 className="text-xl font-semibold text-foreground mb-3">
                            Contact
                        </h2>
                        <p>
                            If you have questions about this privacy policy,
                            please open an issue on our{" "}
                            <a
                                href="https://github.com/bsreeram08/chowser"
                                className="text-foreground underline underline-offset-4 hover:text-primary transition-colors"
                            >
                                GitHub repository
                            </a>
                            .
                        </p>
                    </section>
                </div>
            </main>
            <Footer />
        </div>
    );
};
