import 'https://cdn.jsdelivr.net/gh/orestbida/cookieconsent@3.0.1/dist/cookieconsent.umd.js';

document.documentElement.classList.add('cc--darkmode');

const cc = CookieConsent;

CookieConsent.run({
    guiOptions: {
        consentModal: {
            layout: "box",
            position: "bottom left",
            equalWeightButtons: true,
            flipButtons: false
        },
        preferencesModal: {
            layout: "box",
            position: "right",
            equalWeightButtons: true,
            flipButtons: false
        }
    },
    manageScriptTags: true,
    categories: {
      necessary: {
        readOnly: true
      },
      analytics: {
        enabled: false,
        services: {
          google_analytics: {
            label: 'Google Analytics',
            onAccept: () => {
              gtag('consent', 'update', {
                analytics_storage: 'granted'
              });
            },
            onReject: () => {
              gtag('consent', 'update', {
                analytics_storage: 'denied'
              });
            },
            cookies: [
              { name: /^_ga/ },
              { name: '_gid' }
            ]
          }
        }
      }
    },
    onFirstConsent: ({ cookie }) => {
        console.log('onFirstConsent executed', cc.getUserPreferences(), cookie);
      },
    
      onConsent: ({ cookie }) => {
        console.log('onConsent executed', cc.getUserPreferences());
      },
      onChange: ({ cookie, changedCategories }) => {
        console.log(
          'onChange executed',
          changedCategories,
          cc.getUserPreferences()
        );
      },
    language: {
        default: "en",
        autoDetect: "browser",
        translations: {
            en: {
                consentModal: {
                    title: "Cenimy Twoją prywatność!",
                    description: "Używamy plików cookie, aby pomóc użytkownikom w sprawnej nawigacji i wykonywaniu określonych funkcji. Szczegółowe informacje na temat wszystkich plików cookie odpowiadających poszczególnym kategoriom zgody znajdują się poniżej.",
                    acceptAllBtn: "Akceptuj wszystkie",
                    acceptNecessaryBtn: "Akceptuj niezbędne",
                    showPreferencesBtn: "Dostosuj",
                    footer: "<a target=\"_blank\" href=\"https://www.bernardinum.com.pl/polityka-prywatnosci/\">Polityka prywatności</a>"
                },
                preferencesModal: {
                    title: "Zarządzanie zgodami",
                    acceptAllBtn: "Akceptuj wszystkie",
                    acceptNecessaryBtn: "Odrzuć wszystkie",
                    savePreferencesBtn: "Zapisz moje preferencje",
                    closeIconLabel: "Zamknij",
                    serviceCounterLabel: "Usługa|Usługi",
                    sections: [
                        {
                            title: "Używane pliki cookie",
                            description: "Pliki cookie sklasyfikowane jako „Niezbędne” są przechowywane w przeglądarce użytkownika, ponieważ są niezbędne do włączenia podstawowych funkcji witryny. Korzystamy również z plików cookie innych firm, które pomagają nam analizować sposób korzystania ze strony przez użytkowników, a także przechowywać preferencje użytkownika oraz dostarczać mu istotnych dla niego treści i reklam. Tego typu pliki cookie będą przechowywane w przeglądarce tylko za uprzednią zgodą użytkownika. Można włączyć lub wyłączyć niektóre lub wszystkie te pliki cookie, ale wyłączenie niektórych z nich może wpłynąć na jakość przeglądania."
                        },
                        {
                            title: "Niezbędne pliki  cookie <span class=\"pm__badge\">Zawsze aktywne</span>",
                            description: "Niezbędne pliki cookie mają kluczowe znaczenie dla podstawowych funkcji witryny i witryna nie będzie działać w zamierzony sposób bez nich.Te pliki cookie nie przechowują żadnych danych umożliwiających identyfikację osoby.",
                            linkedCategory: "necessary"
                        },
                        {
                            title: "Analityczne pliki cookie",
                            description: "Analityczne pliki cookie służą do zrozumienia, w jaki sposób użytkownicy wchodzą w interakcję z witryną. Te pliki cookie pomagają dostarczać informacje o metrykach liczby odwiedzających, współczynniku odrzuceń, źródle ruchu itp.",
                            linkedCategory: "analytics"
                        },
                        {
                            title: "Więcej informacji",
                            description: "W przypadku jakichkolwiek pytań związanych z naszą polityką dotyczącą plików cookie i Twoimi wyborami, proszę <a target=\"_blank\" class=\"cc__link\" href=\"https://ksiegarnia.bernardinum.com.pl/dane-kontaktowe \">skontaktować się z nami </a>."
                        }
                    ]
                }
            }
        }
    }
});