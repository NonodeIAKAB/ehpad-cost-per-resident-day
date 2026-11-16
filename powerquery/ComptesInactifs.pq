// ComptesInactifs : comptes déclarés inactifs après validation avec le métier (équivalent du statut "_No CRJ")
// Motifs : pas de chiffre d'affaires, ou le site commande sur un autre de ses comptes.
// Le compte est exclu EN ENTIER : ses ventes ne comptent pas dans le CRJ.
fnLireReference("inactive_accounts.csv", {
    {"account_id", type text}, {"reason", type text},
    {"validated_by", type text}, {"validated_on", type date}})
